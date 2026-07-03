import Foundation

/// Tri-state per-app override: follow the global default, or force on/off.
public enum OverrideChoice: String, Codable, Equatable, CaseIterable, Sendable {
    case useDefault, on, off

    /// The effective boolean once resolved against the global default.
    public func resolved(default defaultValue: Bool) -> Bool {
        switch self {
        case .useDefault: defaultValue
        case .on: true
        case .off: false
        }
    }
}

/// Per-app overrides, keyed by bundle ID in `SettingsState.perApp`. Decoding is
/// tolerant (missing key → default) so files written by older builds keep
/// loading as fields are added.
public struct AppOverrides: Codable, Equatable, Sendable {
    public var completions: OverrideChoice
    public var midLine: OverrideChoice
    public var autocorrect: OverrideChoice
    public var disableAcceptKey: OverrideChoice
    public var improveCompatibility: Bool
    public var customInstructions: String

    public init(
        completions: OverrideChoice = .useDefault,
        midLine: OverrideChoice = .useDefault,
        autocorrect: OverrideChoice = .useDefault,
        disableAcceptKey: OverrideChoice = .useDefault,
        improveCompatibility: Bool = false,
        customInstructions: String = ""
    ) {
        self.completions = completions
        self.midLine = midLine
        self.autocorrect = autocorrect
        self.disableAcceptKey = disableAcceptKey
        self.improveCompatibility = improveCompatibility
        self.customInstructions = customInstructions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        completions = try c.decodeIfPresent(OverrideChoice.self, forKey: .completions) ?? .useDefault
        midLine = try c.decodeIfPresent(OverrideChoice.self, forKey: .midLine) ?? .useDefault
        autocorrect = try c.decodeIfPresent(OverrideChoice.self, forKey: .autocorrect) ?? .useDefault
        disableAcceptKey = try c.decodeIfPresent(OverrideChoice.self, forKey: .disableAcceptKey) ?? .useDefault
        improveCompatibility = try c.decodeIfPresent(Bool.self, forKey: .improveCompatibility) ?? false
        customInstructions = try c.decodeIfPresent(String.self, forKey: .customInstructions) ?? ""
    }
}

/// Usage bookkeeping behind the App Settings list (Cotypist's per-app counters).
public struct AppUsageInfo: Codable, Equatable, Sendable {
    public var displayName: String
    public var suggestionsShown: Int
    public var lastSeen: Date

    public init(displayName: String, suggestionsShown: Int = 0, lastSeen: Date) {
        self.displayName = displayName
        self.suggestionsShown = suggestionsShown
        self.lastSeen = lastSeen
    }
}

/// Global switches and the defaults the per-app tri-states resolve against.
public struct GlobalSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var selectedModel: String?
    public var learningEnabled: Bool
    public var midLineEnabled: Bool          // consumed by subproject E
    public var autocorrectEnabled: Bool      // consumed by subproject F
    public var disableAcceptKeyDefault: Bool

    public init(
        enabled: Bool = true,
        selectedModel: String? = nil,
        learningEnabled: Bool = true,
        midLineEnabled: Bool = false,
        autocorrectEnabled: Bool = true,
        disableAcceptKeyDefault: Bool = false
    ) {
        self.enabled = enabled
        self.selectedModel = selectedModel
        self.learningEnabled = learningEnabled
        self.midLineEnabled = midLineEnabled
        self.autocorrectEnabled = autocorrectEnabled
        self.disableAcceptKeyDefault = disableAcceptKeyDefault
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        selectedModel = try c.decodeIfPresent(String.self, forKey: .selectedModel)
        learningEnabled = try c.decodeIfPresent(Bool.self, forKey: .learningEnabled) ?? true
        midLineEnabled = try c.decodeIfPresent(Bool.self, forKey: .midLineEnabled) ?? false
        autocorrectEnabled = try c.decodeIfPresent(Bool.self, forKey: .autocorrectEnabled) ?? true
        disableAcceptKeyDefault = try c.decodeIfPresent(Bool.self, forKey: .disableAcceptKeyDefault) ?? false
    }
}

/// The whole persisted settings document (settings.json).
public struct SettingsState: Codable, Equatable, Sendable {
    public var version: Int
    public var global: GlobalSettings
    public var perApp: [String: AppOverrides]
    public var appUsage: [String: AppUsageInfo]

    public init(
        version: Int = 1,
        global: GlobalSettings = .init(),
        perApp: [String: AppOverrides] = [:],
        appUsage: [String: AppUsageInfo] = [:]
    ) {
        self.version = version
        self.global = global
        self.perApp = perApp
        self.appUsage = appUsage
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        global = try c.decodeIfPresent(GlobalSettings.self, forKey: .global) ?? .init()
        perApp = try c.decodeIfPresent([String: AppOverrides].self, forKey: .perApp) ?? [:]
        appUsage = try c.decodeIfPresent([String: AppUsageInfo].self, forKey: .appUsage) ?? [:]
    }

    /// Rows for the App Settings list: most-used first, ties by name so the
    /// order is stable.
    public func appsSortedByUsage() -> [(bundleID: String, usage: AppUsageInfo)] {
        appUsage
            .map { (bundleID: $0.key, usage: $0.value) }
            .sorted {
                if $0.usage.suggestionsShown != $1.usage.suggestionsShown {
                    return $0.usage.suggestionsShown > $1.usage.suggestionsShown
                }
                return $0.usage.displayName
                    .localizedCaseInsensitiveCompare($1.usage.displayName) == .orderedAscending
            }
    }
}
