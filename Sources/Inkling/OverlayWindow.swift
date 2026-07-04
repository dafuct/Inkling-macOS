import AppKit

/// A floating, non-interactive window that paints gray ghost text at a point.
final class OverlayWindow {
    private let window: NSWindow
    private let label: NSTextField

    init() {
        label = NSTextField(labelWithString: "")
        label.textColor = .gray
        label.backgroundColor = .clear
        label.isBordered = false
        label.drawsBackground = false
        label.font = .systemFont(ofSize: 14)

        window = NSWindow(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.contentView?.addSubview(label)
    }

    /// `caretBounds` is in global display coords (top-left origin), as returned
    /// by Accessibility. Draws the text on the caret's line, matching the typed
    /// text's font when Accessibility provides it, else scaling to the line height.
    func show(text: String, caretBounds: CGRect, font: NSFont?,
              background: Bool = false, correction: Bool = false) {
        let lineHeight = max(caretBounds.height, 12)
        label.font = font ?? .systemFont(ofSize: max(9, min(40, lineHeight * 0.80)))
        label.stringValue = text
        label.sizeToFit()
        let textSize = label.frame.size

        // AX gives global, top-left-origin coordinates. AppKit uses bottom-left,
        // measured from the PRIMARY screen, so the flip constant is the primary
        // screen's height regardless of which display the caret is on.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let appKitY = primaryHeight - caretBounds.origin.y - lineHeight

        window.setFrame(
            NSRect(x: caretBounds.maxX, y: appKitY, width: textSize.width + 4, height: lineHeight),
            display: true)
        // Center the text vertically on the line so it sits on the same baseline.
        let y = (lineHeight - textSize.height) / 2
        label.frame = NSRect(x: 2, y: y, width: textSize.width, height: textSize.height)

        // Mid-line completions and corrections draw on a translucent pill so they
        // stay legible; a correction uses a distinct tint to read as "replace"
        // rather than "append". Line-end completions draw as plain gray text.
        window.contentView?.wantsLayer = true
        if let layer = window.contentView?.layer {
            let pill = background || correction
            layer.backgroundColor = correction
                ? NSColor.systemYellow.withAlphaComponent(0.30).cgColor
                : (background ? NSColor.windowBackgroundColor.withAlphaComponent(0.85).cgColor
                              : NSColor.clear.cgColor)
            layer.cornerRadius = pill ? 4 : 0
        }
        window.orderFrontRegardless()
    }

    func hide() {
        window.orderOut(nil)
    }
}
