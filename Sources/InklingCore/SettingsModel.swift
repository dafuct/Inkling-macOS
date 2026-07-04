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
    public var clipboardContext: OverrideChoice
    public var screenContext: OverrideChoice
    public var disableAcceptKey: OverrideChoice
    public var alternatives: OverrideChoice
    public var improveCompatibility: Bool
    public var customInstructions: String

    public init(
        completions: OverrideChoice = .useDefault,
        midLine: OverrideChoice = .useDefault,
        autocorrect: OverrideChoice = .useDefault,
        clipboardContext: OverrideChoice = .useDefault,
        screenContext: OverrideChoice = .useDefault,
        disableAcceptKey: OverrideChoice = .useDefault,
        alternatives: OverrideChoice = .useDefault,
        improveCompatibility: Bool = false,
        customInstructions: String = ""
    ) {
        self.completions = completions
        self.midLine = midLine
        self.autocorrect = autocorrect
        self.clipboardContext = clipboardContext
        self.screenContext = screenContext
        self.disableAcceptKey = disableAcceptKey
        self.alternatives = alternatives
        self.improveCompatibility = improveCompatibility
        self.customInstructions = customInstructions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        completions = try c.decodeIfPresent(OverrideChoice.self, forKey: .completions) ?? .useDefault
        midLine = try c.decodeIfPresent(OverrideChoice.self, forKey: .midLine) ?? .useDefault
        autocorrect = try c.decodeIfPresent(OverrideChoice.self, forKey: .autocorrect) ?? .useDefault
        clipboardContext = try c.decodeIfPresent(OverrideChoice.self, forKey: .clipboardContext) ?? .useDefault
        screenContext = try c.decodeIfPresent(OverrideChoice.self, forKey: .screenContext) ?? .useDefault
        disableAcceptKey = try c.decodeIfPresent(OverrideChoice.self, forKey: .disableAcceptKey) ?? .useDefault
        alternatives = try c.decodeIfPresent(OverrideChoice.self, forKey: .alternatives) ?? .useDefault
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

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        suggestionsShown = try c.decodeIfPresent(Int.self, forKey: .suggestionsShown) ?? 0
        lastSeen = try c.decodeIfPresent(Date.self, forKey: .lastSeen) ?? Date(timeIntervalSince1970: 0)
    }
}

/// Global switches and the defaults the per-app tri-states resolve against.
public struct GlobalSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var selectedModel: String?
    public var collectInputs: Bool           // was learningEnabled; master capture+learn gate
    public var storeWithoutAccepted: Bool    // store inputs even without an accepted completion
    public var personalizeLevel: Int         // 0=off … MemoryEngine.maxPersonalizationLevel
    public var customInstructions: String    // global custom AI instructions (subproject D)
    public var instructionPreambleEnabled: Bool  // default-off gate for prompt injection
    public var useClipboardContext: Bool     // consumed by subproject G1 (clipboard context)
    public var useScreenContext: Bool        // consumed by subproject G2 (screen context)
    public var showAlternatives: Bool        // consumed by subproject H (alternatives picker)
    public var midLineEnabled: Bool          // consumed by subproject E
    public var autocorrectEnabled: Bool      // consumed by subproject F
    public var disableAcceptKeyDefault: Bool

    public init(
        enabled: Bool = true,
        selectedModel: String? = nil,
        collectInputs: Bool = true,
        storeWithoutAccepted: Bool = true,
        personalizeLevel: Int = 1,
        customInstructions: String = "",
        instructionPreambleEnabled: Bool = false,
        useClipboardContext: Bool = false,
        useScreenContext: Bool = false,
        showAlternatives: Bool = false,
        midLineEnabled: Bool = false,
        autocorrectEnabled: Bool = true,
        disableAcceptKeyDefault: Bool = false
    ) {
        self.enabled = enabled
        self.selectedModel = selectedModel
        self.collectInputs = collectInputs
        self.storeWithoutAccepted = storeWithoutAccepted
        self.personalizeLevel = personalizeLevel
        self.customInstructions = customInstructions
        self.instructionPreambleEnabled = instructionPreambleEnabled
        self.useClipboardContext = useClipboardContext
        self.useScreenContext = useScreenContext
        self.showAlternatives = showAlternatives
        self.midLineEnabled = midLineEnabled
        self.autocorrectEnabled = autocorrectEnabled
        self.disableAcceptKeyDefault = disableAcceptKeyDefault
    }

    // Explicit keys so the decoder can fall back to the legacy `learningEnabled`
    // name. `learningEnabled` has no matching property, so hand-written encoding
    // never writes it — it exists only for reading pre-rename files.
    enum CodingKeys: String, CodingKey {
        case enabled, selectedModel, collectInputs, learningEnabled
        case storeWithoutAccepted, personalizeLevel
        case customInstructions, instructionPreambleEnabled
        case useClipboardContext
        case useScreenContext
        case showAlternatives
        case midLineEnabled, autocorrectEnabled, disableAcceptKeyDefault
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        selectedModel = try c.decodeIfPresent(String.self, forKey: .selectedModel)
        collectInputs = try c.decodeIfPresent(Bool.self, forKey: .collectInputs)
            ?? c.decodeIfPresent(Bool.self, forKey: .learningEnabled) ?? true
        storeWithoutAccepted = try c.decodeIfPresent(Bool.self, forKey: .storeWithoutAccepted) ?? true
        personalizeLevel = try c.decodeIfPresent(Int.self, forKey: .personalizeLevel) ?? 1
        customInstructions = try c.decodeIfPresent(String.self, forKey: .customInstructions) ?? ""
        instructionPreambleEnabled = try c.decodeIfPresent(Bool.self, forKey: .instructionPreambleEnabled) ?? false
        useClipboardContext = try c.decodeIfPresent(Bool.self, forKey: .useClipboardContext) ?? false
        useScreenContext = try c.decodeIfPresent(Bool.self, forKey: .useScreenContext) ?? false
        showAlternatives = try c.decodeIfPresent(Bool.self, forKey: .showAlternatives) ?? false
        midLineEnabled = try c.decodeIfPresent(Bool.self, forKey: .midLineEnabled) ?? false
        autocorrectEnabled = try c.decodeIfPresent(Bool.self, forKey: .autocorrectEnabled) ?? true
        disableAcceptKeyDefault = try c.decodeIfPresent(Bool.self, forKey: .disableAcceptKeyDefault) ?? false
    }

    // `learningEnabled` has no stored property, so a custom init(from:) disables
    // encode(to:) synthesis entirely. Written by hand; deliberately omits the
    // `.learningEnabled` key (decode-only).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encodeIfPresent(selectedModel, forKey: .selectedModel)
        try c.encode(collectInputs, forKey: .collectInputs)
        try c.encode(storeWithoutAccepted, forKey: .storeWithoutAccepted)
        try c.encode(personalizeLevel, forKey: .personalizeLevel)
        try c.encode(customInstructions, forKey: .customInstructions)
        try c.encode(instructionPreambleEnabled, forKey: .instructionPreambleEnabled)
        try c.encode(useClipboardContext, forKey: .useClipboardContext)
        try c.encode(useScreenContext, forKey: .useScreenContext)
        try c.encode(showAlternatives, forKey: .showAlternatives)
        try c.encode(midLineEnabled, forKey: .midLineEnabled)
        try c.encode(autocorrectEnabled, forKey: .autocorrectEnabled)
        try c.encode(disableAcceptKeyDefault, forKey: .disableAcceptKeyDefault)
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
