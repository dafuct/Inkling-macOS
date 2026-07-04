import CoreGraphics
import Foundation
import InklingCore

/// Owns a CGEventTap. When a suggestion is visible it swallows backtick (accept)
/// and Esc (dismiss); otherwise it passes keys through and reports them.
final class EventTapController {
    var suggestionVisible = false
    var onKeyDown: (() -> Void)?
    var onAccept: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onType: ((String) -> Void)?
    var onDelete: (() -> Void)?
    /// Consulted before swallowing the accept key while a suggestion is
    /// visible; return false to let the keystroke pass through (per-app
    /// "Disable accept key"). nil means always swallow.
    var shouldSwallowAccept: (() -> Bool)?
    var onCycle: (() -> Void)?
    /// True while the visible suggestion has ≥2 cyclable alternatives; consulted
    /// before swallowing Option+backtick as a cycle.
    var alternativesAvailable = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let acceptKeyCode: Int64 = 0x32  // kVK_ANSI_Grave (backtick `)
    private let escKeyCode: Int64 = 0x35  // kVK_Escape
    private let deleteKeyCode: Int64 = 0x33  // kVK_Delete (backspace)

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
                let optionHeld = event.flags.contains(.maskAlternate)
                switch AcceptKeyAction.classify(
                    isAcceptKey: keyCode == acceptKeyCode, optionHeld: optionHeld,
                    suggestionVisible: true, alternativesAvailable: alternativesAvailable) {
                case .cycle:
                    onCycle?()
                    return nil
                case .accept:
                    // swallow ` (accept) unless the accept key is disabled for this app
                    if shouldSwallowAccept?() ?? true {
                        onAccept?()
                        return nil
                    }
                case .passThrough:
                    break
                }
                if keyCode == escKeyCode { onDismiss?(); return nil }  // swallow Esc
            }
            // Capture for personalization (skip when a shortcut modifier is held).
            let flags = event.flags
            let hasCmdOrCtrl = flags.contains(.maskCommand) || flags.contains(.maskControl)
            if !hasCmdOrCtrl {
                if keyCode == deleteKeyCode {
                    onDelete?()
                } else if let s = typedString(event), isCapturable(s) {
                    onType?(s)
                }
            }
            onKeyDown?()
        }
        return Unmanaged.passUnretained(event)
    }

    /// The Unicode string a key event would insert (respecting modifiers/layout).
    private func typedString(_ event: CGEvent) -> String? {
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        guard length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }

    /// True for ordinary printable text (one or more chars, none a control char).
    private func isCapturable(_ s: String) -> Bool {
        guard !s.isEmpty else { return false }
        return s.unicodeScalars.allSatisfy { !($0.value < 0x20 || $0.value == 0x7F) }
    }
}
