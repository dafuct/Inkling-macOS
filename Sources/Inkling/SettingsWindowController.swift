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
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            w.title = "Inkling Settings"
            // Hosting via a controller (not a bare view) lets SwiftUI's
            // NavigationSplitView plumb its sidebar-toggle into the window
            // toolbar instead of floating it in the content area.
            w.contentViewController = NSHostingController(
                rootView: SettingsRootView(initialSection: section ?? .general))
            // A unified toolbar gives the split view's collapse control a home
            // and produces the standard macOS Settings-window titlebar.
            let toolbar = NSToolbar(identifier: "InklingSettingsToolbar")
            toolbar.displayMode = .iconOnly
            w.toolbar = toolbar
            w.toolbarStyle = .unified
            w.titlebarAppearsTransparent = false
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
