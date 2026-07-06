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

        var caretBounds = CaretGeometry.caretRect(
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

        // Fallback caret-geometry ladder for editors that refuse per-glyph bounds
        // even after full AX is enabled — notably Electron/Chromium (Slack,
        // Discord, Notion), where the focused node answers text but not glyph
        // rects. Each rung is sanity-checked against the field frame so a bad
        // reading degrades to "no suggestion", never a mis-placed one. Only runs
        // when the reliable rungs above return nil, so native apps never pay for
        // it. See wiki [[inkling-caret-geometry]].
        if caretBounds == nil {
            // The focused element's frame, in global top-left coords, used as an
            // anchor and as a sanity box for the two rungs below.
            func frame(of el: AXUIElement) -> CGRect? {
                var ref: CFTypeRef?
                if AXUIElementCopyAttributeValue(el, "AXFrame" as CFString, &ref) == .success,
                   let ref, CFGetTypeID(ref) == AXValueGetTypeID() {
                    var r = CGRect.zero
                    if AXValueGetValue(ref as! AXValue, .cgRect, &r), r.height > 0 { return r }
                }
                var posRef: CFTypeRef?
                var sizeRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef) == .success,
                      AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeRef) == .success,
                      let posRef, let sizeRef,
                      CFGetTypeID(posRef) == AXValueGetTypeID(), CFGetTypeID(sizeRef) == AXValueGetTypeID()
                else { return nil }
                var p = CGPoint.zero, s = CGSize.zero
                guard AXValueGetValue(posRef as! AXValue, .cgPoint, &p),
                      AXValueGetValue(sizeRef as! AXValue, .cgSize, &s) else { return nil }
                return CGRect(origin: p, size: s)
            }
            let elementFrame = frame(of: element)

            func bounds(of node: AXUIElement, forRange r: CFRange) -> CGRect? {
                guard r.location >= 0, r.length >= 0 else { return nil }
                var range = r
                guard let v = AXValueCreate(.cfRange, &range) else { return nil }
                var ref: CFTypeRef?
                guard AXUIElementCopyParameterizedAttributeValue(
                    node, kAXBoundsForRangeParameterizedAttribute as CFString, v, &ref) == .success,
                      let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
                var rect = CGRect.zero
                guard AXValueGetValue(ref as! AXValue, .cgRect, &rect) else { return nil }
                return rect
            }

            // Rung 4 — line geometry: some editors refuse a single-char range but
            // answer for a whole line, so measure line-start→caret and take its
            // trailing edge. Correct y/height even mid-line.
            func lineBasedCaretBounds() -> CGRect? {
                var lineRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(
                    element, kAXInsertionPointLineNumberAttribute as CFString, &lineRef) == .success,
                      let lineNum = lineRef as? Int, lineNum >= 0 else { return nil }
                var rangeRef: CFTypeRef?
                guard AXUIElementCopyParameterizedAttributeValue(
                    element, kAXRangeForLineParameterizedAttribute as CFString,
                    NSNumber(value: lineNum), &rangeRef) == .success,
                      let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() else { return nil }
                var lineRange = CFRange()
                guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &lineRange) else { return nil }
                let prefixLen = caretIndex - lineRange.location
                if prefixLen > 0,
                   let b = bounds(of: element, forRange: CFRange(location: lineRange.location, length: prefixLen)),
                   b.height > 0 {
                    return CGRect(x: b.maxX, y: b.minY, width: 0, height: b.height)
                }
                if let lb = bounds(of: element, forRange: lineRange), lb.height > 0 {
                    return CGRect(x: lb.minX, y: lb.minY, width: 0, height: lb.height)
                }
                return nil
            }

            // Rung 5 — descendant search: Electron nests the real text node under a
            // wrapper, so BFS the subtree (hard-capped) for a node that answers
            // caret geometry via its OWN selection.
            func descendantCaretBounds() -> CGRect? {
                func children(of node: AXUIElement) -> [AXUIElement] {
                    var ref: CFTypeRef?
                    guard AXUIElementCopyAttributeValue(node, kAXChildrenAttribute as CFString, &ref) == .success,
                          let kids = ref as? [AXUIElement] else { return [] }
                    return kids
                }
                func caretBoundsViaSelection(of node: AXUIElement) -> CGRect? {
                    var rangeRef: CFTypeRef?
                    guard AXUIElementCopyAttributeValue(
                        node, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
                          let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() else { return nil }
                    var sel = CFRange()
                    guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &sel) else { return nil }
                    let loc = sel.location
                    return CaretGeometry.caretRect(
                        prevChar: loc > 0 ? bounds(of: node, forRange: CFRange(location: loc - 1, length: 1)) : nil,
                        atCaret: bounds(of: node, forRange: CFRange(location: loc, length: 1)),
                        marker: nil)
                }
                var queue = children(of: element)
                var visited = 0
                while !queue.isEmpty, visited < 80 {
                    let node = queue.removeFirst()
                    visited += 1
                    if let r = caretBoundsViaSelection(of: node), r.height > 0 { return r }
                    queue.append(contentsOf: children(of: node).prefix(40))
                }
                return nil
            }

            // Rung 6 — frame anchor: last resort for a SINGLE-LINE-ish field with
            // no glyph geometry at all (a Slack-height composer). Measure the
            // line prefix to estimate x. Hard-gated to short fields so a tall
            // editor is never mis-anchored.
            func frameAnchorCaretBounds() -> CGRect? {
                guard let frame = elementFrame, frame.width > 0 else { return nil }
                let f = caretFont ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
                let lineH = max(f.ascender - f.descender + f.leading, f.pointSize * 1.2)
                guard frame.height <= lineH * 2.2 else { return nil }   // single-line only
                let ns = text as NSString
                let clamped = max(0, min(caretIndex, ns.length))
                let nl = ns.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: clamped))
                let start = nl.location == NSNotFound ? 0 : nl.location + 1
                let prefix = ns.substring(with: NSRange(location: start, length: clamped - start))
                let width = (prefix as NSString).size(withAttributes: [.font: f]).width
                let x = frame.minX + width
                guard x <= frame.maxX else { return nil }
                return CGRect(x: x, y: frame.minY, width: 0, height: lineH)
            }

            caretBounds = lineBasedCaretBounds() ?? descendantCaretBounds()
            // Reject any glyph-derived fallback that lands outside the field.
            if let b = caretBounds, let f = elementFrame, !f.insetBy(dx: -8, dy: -8).intersects(b) {
                caretBounds = nil
            }
            if caretBounds == nil { caretBounds = frameAnchorCaretBounds() }
        }

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
