import AppKit
import ApplicationServices

/// Chromium/Electron apps (Slack, Discord, Notion desktop, Chrome) expose text
/// via Accessibility but build caret/character *geometry* only when they believe
/// a screen reader is attached. Chromium watches for a screen-reader signal set
/// as an attribute on the app element: `AXEnhancedUserInterface` (Chrome + older
/// Electron) and Electron's dedicated `AXManualAccessibility`. Setting them makes
/// Chromium build its inline-text-box layer, after which the existing text-marker
/// geometry path in `FocusContextProvider` starts returning caret bounds — the
/// same path that fixed Apple Notes. VoiceOver does exactly this.
///
/// This is why Slack gave us `kAXValue` (text) but `caretBounds == nil`: the
/// skeletal tree answers text queries, but only full mode builds glyph rects.
///
/// We enable it lazily — only when a focused element yields text but no caret
/// bounds — and at most once per pid, skipping apps where full-accessibility mode
/// changes the app's own behaviour in a user-hostile way (VS Code / Cursor flip
/// into screen-reader mode, disabling word wrap and IntelliSense).
@MainActor
enum ElectronAXActivator {
    /// pids already attempted, so the flags are set at most once per app launch.
    /// A relaunched app gets a new pid and is retried naturally.
    private static var attempted: Set<pid_t> = []

    /// Bundle ids where enabling full accessibility visibly degrades the app
    /// itself — never touch these; the user can opt in via the app's own setting.
    private static let denylist: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.visualstudio.code.oss",
        "com.todesktop.230313mzl4w4u92",   // Cursor
        "com.exafunction.windsurf",        // Windsurf
    ]

    /// When the focused element gives text but no caret geometry, flip the
    /// Chromium/Electron screen-reader flags on its app element. Returns true only
    /// on a *fresh* activation, so the caller can schedule a re-read once Chromium
    /// finishes rebuilding its tree (~50–500ms later) instead of waiting for the
    /// next keystroke. Cheap and idempotent: after the first attempt for a pid it
    /// returns false immediately.
    @discardableResult
    static func activateIfNeeded() -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else { return false }
        let element = focusedRef as! AXUIElement

        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid > 0 else { return false }
        guard !attempted.contains(pid) else { return false }
        attempted.insert(pid)   // one shot per pid, regardless of outcome

        if let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
           denylist.contains(bundleID) {
            NSLog("Inkling: skipping Electron AX for denylisted \(bundleID)")
            return false
        }

        // Ignore the AXError: some Electron versions report .attributeUnsupported
        // while still applying the change (electron/electron#37465). Success is
        // verified empirically by caret bounds appearing on the follow-up read.
        let appEl = AXUIElementCreateApplication(pid)
        _ = AXUIElementSetAttributeValue(appEl, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(appEl, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        NSLog("Inkling: enabled Electron/Chromium full AX for pid \(pid)")
        return true
    }
}
