import Foundation

/// One-time import of the legacy UserDefaults keys into a fresh SettingsState.
/// Pure: the caller supplies the legacy values (nil = key was never set).
public enum SettingsMigration {
    public static func fromLegacy(
        enabled: Bool?, selectedModel: String?, learningEnabled: Bool?
    ) -> SettingsState {
        var state = SettingsState()
        state.global.enabled = enabled ?? true
        state.global.selectedModel = selectedModel
        state.global.collectInputs = learningEnabled ?? true
        return state
    }
}
