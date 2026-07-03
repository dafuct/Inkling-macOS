import AppKit
import ApplicationServices
import CoreGraphics
import InklingCore

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

        // Per-character pixel bounds via AXBoundsForRange (global display coords,
        // top-left origin). Editors return these inconsistently, so the final
        // caret rect is chosen by CaretGeometry below.
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

        // WebKit-style editors (Apple Notes) return a useless zero-size rect from
        // AXBoundsForRange but DO implement the text-marker geometry API, which
        // gives the real caret rect. Use it when the character-range API fails.
        func textMarkerCaretBounds() -> CGRect? {
            var markerRange: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                element, "AXSelectedTextMarkerRange" as CFString, &markerRange) == .success,
                  let markerRange else { return nil }
            var boundsRef: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(
                element, "AXBoundsForTextMarkerRange" as CFString, markerRange, &boundsRef) == .success,
                  let boundsRef, CFGetTypeID(boundsRef) == AXValueGetTypeID() else { return nil }
            var rect = CGRect.zero
            guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect) else { return nil }
            return rect.height > 0 ? rect : nil
        }

        let caretBounds = CaretGeometry.caretRect(
            prevChar: caretIndex > 0 ? bounds(forLocation: caretIndex - 1) : nil,
            atCaret: bounds(forLocation: caretIndex),
            marker: textMarkerCaretBounds())

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

    /// The currently focused UI element, or nil. Cheaper than `currentReadout()`
    /// (no text/bounds/font) — used to detect focus-session boundaries.
    static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            system, kAXFocusedUIElementAttribute as CFString, &focusedRef
        ) == .success, let focusedRef,
        CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return nil }
        return (focusedRef as! AXUIElement)
    }

    /// The text value of a specific element (read from a retained element even
    /// after focus has moved on). Returns nil for secure fields or non-text.
    static func text(of element: AXUIElement) -> String? {
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
           let role = roleRef as? String, role == "AXSecureTextField" { return nil }
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let value = valueRef as? String else { return nil }
        return value
    }
}
