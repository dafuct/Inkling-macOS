import CoreGraphics

/// Picks the caret rectangle from the candidate bounds an editor exposes through
/// Accessibility. The returned rect's `maxX` is the caret's x position and its
/// y/height describe the caret's line — so callers can position ghost text at
/// `result.maxX`.
///
/// Editors disagree wildly about `AXBoundsForRange`:
///  - TextEdit / NSTextView: the at-caret range fails at end-of-text.
///  - Apple Notes (large element): the at-caret range returns a bogus full-width
///    end-of-line fill rect — using its `maxX` flings the caret to the margin.
///  - Apple Notes (small element): range bounds are zero-size; only the
///    text-marker API gives a usable insertion point.
///
/// Strategy: prefer the preceding char's trailing edge (a normal, reliable glyph
/// rect = the caret), then the at-caret char's leading edge collapsed to zero
/// width (so a bogus fill width can't move the caret), then the text-marker
/// insertion point. Rects without a real line height are skipped.
public enum CaretGeometry {
    public static func caretRect(prevChar: CGRect?, atCaret: CGRect?, marker: CGRect?) -> CGRect? {
        func usable(_ r: CGRect?) -> CGRect? { (r?.height ?? 0) > 0 ? r : nil }
        if let p = usable(prevChar) { return p }
        if let a = usable(atCaret) {
            return CGRect(x: a.minX, y: a.minY, width: 0, height: a.height)
        }
        return usable(marker)
    }
}
