import ApplicationServices

/// Thin wrapper over the Accessibility trust API. Calling with `prompt: true`
/// makes macOS show the "open System Settings" dialog the first time.
enum PermissionsManager {
    @discardableResult
    static func isAccessibilityTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
