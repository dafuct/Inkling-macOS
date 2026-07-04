import AppKit
import SwiftUI

/// Lazily creates and reuses the settings window. The app is an accessory
/// (menu-bar) agent, so we activate explicitly to bring the window forward.
final class SettingsWindowController {
    private var window: NSWindow?

    func show(select section: SettingsSection? = nil) {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            w.title = "Inkling Settings"
            w.contentView = NSHostingView(rootView: SettingsRootView(initialSection: section ?? .general))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
