import AppKit
import ApplicationServices
import CoreGraphics

/// What we managed to read from the currently focused text element.
struct CaretReadout {
    let text: String
    let caretIndex: Int        // UTF-16 offset
    let caretBounds: CGRect?   // global display coords, top-left origin
    let font: NSFont?          // the focused text's font, if Accessibility exposes it
}

enum FocusContextProvider {
    /// True if the focused element is a secure (password) field. A lightweight
    /// role/subrole check used to gate learning per keystroke.
    static func isSecureFieldFocused() -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            system, kAXFocusedUIElementAttribute as CFString, &focusedRef
        ) == .success, let focusedRef,
        CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return false }
        let element = focusedRef as! AXUIElement
        let secureRole = "AXSecureTextField"
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
           let role = roleRef as? String, role == secureRole { return true }
        var subroleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef) == .success,
           let subrole = subroleRef as? String, subrole == secureRole { return true }
        return false
    }

    /// Reads the focused element. Returns nil for non-text or secure (password)
    /// fields, or when Accessibility exposes nothing usable.
    static func currentReadout() -> CaretReadout? {
        let system = AXUIElementCreateSystemWide()

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            system, kAXFocusedUIElementAttribute as CFString, &focusedRef
        ) == .success, let focusedRef else { return nil }
        guard CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return nil }
        let element = focusedRef as! AXUIElement

        // Never read password fields. A secure field reports "AXSecureTextField"
        // as its role OR subrole depending on the app, so check both. (The Swift
        // overlay for this SDK doesn't export kAXSecureTextFieldRole, so we use
        // its documented literal value.)
        let secureRole = "AXSecureTextField"
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
           let role = roleRef as? String, role == secureRole {
            return nil
        }
        var subroleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef) == .success,
           let subrole = subroleRef as? String, subrole == secureRole {
            return nil
        }

        // Text value.
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let text = valueRef as? String else { return nil }

        // Caret offset (selected range location). Default to end of text.
        var caretIndex = text.utf16.count
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() {
            var cfRange = CFRange()
            if AXValueGetValue(rangeRef as! AXValue, .cfRange, &cfRange) {
                caretIndex = cfRange.location
            }
        }

        // Caret pixel bounds via the parameterized bounds-for-range attribute.
        // Asking for the char AT the caret fails when the caret is at end-of-text
        // (the common case while typing), so fall back to the preceding char and
        // use its trailing edge — which is exactly where the caret sits. Bounds
        // come back in global display coords with a top-left origin.
        func bounds(forLocation loc: Int) -> CGRect? {
            guard loc >= 0 else { return nil }
            var range = CFRange(location: loc, length: 1)
            guard let rangeValue = AXValueCreate(.cfRange, &range) else { return nil }
            var boundsRef: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXBoundsForRangeParameterizedAttribute as CFString,
                rangeValue,
                &boundsRef
            ) == .success, let boundsRef,
                  CFGetTypeID(boundsRef) == AXValueGetTypeID() else { return nil }
            var rect = CGRect.zero
            guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect) else { return nil }
            return rect
        }

        let caretBounds = bounds(forLocation: caretIndex) ?? bounds(forLocation: caretIndex - 1)

        // The font of the text near the caret, so the ghost text matches exactly.
        func font(forLocation loc: Int) -> NSFont? {
            guard loc >= 0 else { return nil }
            var range = CFRange(location: loc, length: 1)
            guard let rangeValue = AXValueCreate(.cfRange, &range) else { return nil }
            var ref: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXAttributedStringForRangeParameterizedAttribute as CFString,
                rangeValue,
                &ref
            ) == .success, let attr = ref as? NSAttributedString, attr.length > 0 else { return nil }
            if let f = attr.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
                return f
            }
            // Some apps expose an AX font dictionary instead of an NSFont.
            if let dict = attr.attribute(NSAttributedString.Key("AXFont"), at: 0, effectiveRange: nil) as? [String: Any],
               let size = (dict["AXFontSize"] as? CGFloat) ?? (dict["AXFontSize"] as? Double).map({ CGFloat($0) }) {
                if let name = dict["AXFontName"] as? String, let f = NSFont(name: name, size: size) {
                    return f
                }
                return NSFont.systemFont(ofSize: size)
            }
            return nil
        }
        let caretFont = font(forLocation: max(0, caretIndex - 1)) ?? font(forLocation: caretIndex)

        return CaretReadout(
            text: text, caretIndex: caretIndex, caretBounds: caretBounds, font: caretFont)
    }
}
