import Foundation

/// Persisted user settings (UserDefaults). `enabled` defaults to true; the
/// selected model is a directory name under ModelConfig.modelsRoot.
enum Settings {
    private static let defaults = UserDefaults.standard
    private static let enabledKey = "InklingEnabled"
    private static let modelKey = "InklingSelectedModel"

    static var enabled: Bool {
        get { defaults.object(forKey: enabledKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: enabledKey) }
    }

    static var selectedModel: String? {
        get { defaults.string(forKey: modelKey) }
        set { defaults.set(newValue, forKey: modelKey) }
    }

    private static let learningKey = "InklingLearningEnabled"

    /// Whether new typing is captured into PersonalMemory. Defaults to true.
    /// Gates capture only — existing learned data is still used when paused.
    static var learningEnabled: Bool {
        get { defaults.object(forKey: learningKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: learningKey) }
    }
}
