import AppKit

/// The app the user is typing in right now. Cheap NSWorkspace lookups —
/// safe to call per keystroke on the main thread.
enum FrontmostApp {
    static var bundleID: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
    static var name: String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }
}
