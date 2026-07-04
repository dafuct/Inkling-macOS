import AppKit

// Program entry runs on the main thread; assume main-actor isolation so the
// @MainActor AppDelegate can be constructed and wired here.
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    let app = NSApplication.shared
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // no Dock icon
    app.run()
}
