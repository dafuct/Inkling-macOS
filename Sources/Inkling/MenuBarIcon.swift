import AppKit

/// The menu-bar status-item glyph: a text caret followed by a short "suggestion"
/// line — the monochrome, template-image version of the app icon's motif. Being
/// a template image, the system tints it for light/dark menu bars automatically.
enum MenuBarIcon {
    static func image() -> NSImage {
        let img = NSImage(size: NSSize(width: 20, height: 15), flipped: false) { rect in
            NSColor.black.setFill()
            let S = rect.height, W = rect.width
            let cw = S * 0.12, ch = S * 0.80
            let caret = NSRect(x: W * 0.28 - cw / 2, y: (S - ch) / 2, width: cw, height: ch)
            NSBezierPath(roundedRect: caret, xRadius: cw / 2, yRadius: cw / 2).fill()
            let lh = S * 0.16, lw = W * 0.42
            let line = NSRect(x: W * 0.42, y: (S - lh) / 2, width: lw, height: lh)
            NSBezierPath(roundedRect: line, xRadius: lh / 2, yRadius: lh / 2).fill()
            return true
        }
        img.isTemplate = true
        return img
    }
}
