import Foundation

/// The single read path for runtime settings: per-app override if set,
/// otherwise the global default. Pure functions over SettingsState.
public enum EffectiveSettings {
    /// Master switch ANDed with the per-app choice (per-app default is "on"),
    /// so an explicit per-app "On" cannot beat a globally disabled app.
    public static func completionsEnabled(state: SettingsState, bundleID: String?) -> Bool {
        guard state.global.enabled else { return false }
        return choice(state, bundleID, \.completions).resolved(default: true)
    }

    /// False when the accept key is disabled for this app (backtick then types
    /// through as a normal character).
    public static func acceptKeyEnabled(state: SettingsState, bundleID: String?) -> Bool {
        !choice(state, bundleID, \.disableAcceptKey)
            .resolved(default: state.global.disableAcceptKeyDefault)
    }

    public static func midLineEnabled(state: SettingsState, bundleID: String?) -> Bool {
        choice(state, bundleID, \.midLine).resolved(default: state.global.midLineEnabled)
    }

    public static func autocorrectEnabled(state: SettingsState, bundleID: String?) -> Bool {
        choice(state, bundleID, \.autocorrect).resolved(default: state.global.autocorrectEnabled)
    }

    public static func clipboardContextEnabled(state: SettingsState, bundleID: String?) -> Bool {
        choice(state, bundleID, \.clipboardContext).resolved(default: state.global.useClipboardContext)
    }

    public static func screenContextEnabled(state: SettingsState, bundleID: String?) -> Bool {
        choice(state, bundleID, \.screenContext).resolved(default: state.global.useScreenContext)
    }

    /// Combined instructions: the global baseline plus the per-app supplement
    /// (blank-line separated). nil when both are empty. (Consumer: the engine
    /// wiring, subproject D.)
    public static func customInstructions(state: SettingsState, bundleID: String?) -> String? {
        let global = state.global.customInstructions
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let perApp = (bundleID.flatMap { state.perApp[$0]?.customInstructions } ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch (global.isEmpty, perApp.isEmpty) {
        case (true, true): return nil
        case (false, true): return global
        case (true, false): return perApp
        case (false, false): return global + "\n\n" + perApp
        }
    }

    public static func improveCompatibility(state: SettingsState, bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return state.perApp[bundleID]?.improveCompatibility ?? false
    }

    private static func choice(
        _ state: SettingsState, _ bundleID: String?,
        _ keyPath: KeyPath<AppOverrides, OverrideChoice>
    ) -> OverrideChoice {
        guard let bundleID, let overrides = state.perApp[bundleID] else { return .useDefault }
        return overrides[keyPath: keyPath]
    }
}
