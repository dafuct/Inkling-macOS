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
    /// by Accessibility. Draws the text to the right of the caret.
    func show(text: String, caretBounds: CGRect) {
        label.stringValue = text
        label.sizeToFit()
        let size = label.frame.size

        // AX gives global, top-left-origin coordinates. AppKit uses bottom-left,
        // measured from the PRIMARY screen, so the flip constant is the primary
        // screen's height regardless of which display the caret is on.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let appKitY = primaryHeight - caretBounds.origin.y - caretBounds.height

        let frame = NSRect(
            x: caretBounds.maxX,
            y: appKitY,
            width: size.width + 4,
            height: max(size.height, caretBounds.height)
        )
        window.setFrame(frame, display: true)
        label.frame = NSRect(x: 2, y: 0, width: size.width, height: frame.height)
        window.orderFrontRegardless()
    }

    func hide() {
        window.orderOut(nil)
    }
}
