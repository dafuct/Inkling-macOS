import CoreGraphics
import Foundation

/// Owns a CGEventTap. Swallows Tab when `suggestionVisible` is true; otherwise
/// passes every keyDown through and reports it via `onKeyDown`.
final class EventTapController {
    /// Set true while a suggestion is on screen; gates Tab swallowing.
    var suggestionVisible = false
    /// Fired for each keyDown that is NOT swallowed (used to refresh context).
    var onKeyDown: (() -> Void)?
    /// Fired when Tab is swallowed (the accept gesture).
    var onAccept: (() -> Void)?

    private var eventTap: CFMachPort?
    private let tabKeyCode: Int64 = 0x30 // kVK_Tab

    /// Creates and enables the tap on the current run loop. Returns false if the
    /// OS refused (usually means Accessibility/Input Monitoring is not granted).
    func start() -> Bool {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let controller = Unmanaged<EventTapController>
                .fromOpaque(refcon!)
                .takeUnretainedValue()
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
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == tabKeyCode && suggestionVisible {
                onAccept?()
                return nil // swallow Tab
            }
            onKeyDown?()
        }
        return Unmanaged.passUnretained(event)
    }
}
