import ApplicationServices
import CoreGraphics

/// What we managed to read from the currently focused text element.
struct CaretReadout {
    let text: String
    let caretIndex: Int        // UTF-16 offset
    let caretBounds: CGRect?   // global display coords, top-left origin
}

enum FocusContextProvider {
    /// Reads the focused element. Returns nil for non-text or secure (password)
    /// fields, or when Accessibility exposes nothing usable.
    static func currentReadout() -> CaretReadout? {
        let system = AXUIElementCreateSystemWide()

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            system, kAXFocusedUIElementAttribute as CFString, &focusedRef
        ) == .success, let focusedRef else { return nil }
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
           let rangeRef {
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
            ) == .success, let boundsRef else { return nil }
            var rect = CGRect.zero
            guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect) else { return nil }
            return rect
        }

        let caretBounds = bounds(forLocation: caretIndex) ?? bounds(forLocation: caretIndex - 1)

        return CaretReadout(text: text, caretIndex: caretIndex, caretBounds: caretBounds)
    }
}
