import CoreGraphics
import Foundation

/// Owns a CGEventTap. When a suggestion is visible it swallows backtick (accept)
/// and Esc (dismiss); otherwise it passes keys through and reports them.
final class EventTapController {
    var suggestionVisible = false
    var onKeyDown: (() -> Void)?
    var onAccept: (() -> Void)?
    var onDismiss: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let acceptKeyCode: Int64 = 0x32  // kVK_ANSI_Grave (backtick `)
    private let escKeyCode: Int64 = 0x35  // kVK_Escape

    func start() -> Bool {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let controller = Unmanaged<EventTapController>.fromOpaque(refcon!).takeUnretainedValue()
            return controller.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// Disables the tap and tears down its run-loop source. Safe to call once.
    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if type == .keyDown {
            // Ignore keystrokes we synthesized ourselves (accepted text).
            if event.getIntegerValueField(.eventSourceUserData) == TextInserter.marker {
                return Unmanaged.passUnretained(event)
            }
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if suggestionVisible {
                if keyCode == acceptKeyCode { onAccept?(); return nil }   // swallow ` (accept)
                if keyCode == escKeyCode { onDismiss?(); return nil }  // swallow Esc
            }
            onKeyDown?()
        }
        return Unmanaged.passUnretained(event)
    }
}
