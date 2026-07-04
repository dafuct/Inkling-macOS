import Foundation
import InklingCore

/// Chosen local model + generation settings + prompt for the real engine.
enum ModelConfig {
    /// Root folder holding installed model directories. Resolved portably so the
    /// app runs as a distributed bundle, a user install, or a dev checkout:
    ///   1. models bundled inside the app (Contents/Resources/models),
    ///   2. ~/Library/Application Support/Inkling/models,
    ///   3. the developer source checkout (fallback).
    /// The single writable install destination for downloaded models:
    /// ~/Library/Application Support/Inkling/models (created on demand).
    static let installRoot: URL = {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(filePath: NSHomeDirectory()).appending(path: "Library/Application Support")
        return ModelInstallLocator.installRoot(appSupport: appSupport)
    }()

    /// Root folder searched for installed models. Prefers models bundled inside
    /// the app, then the install root once populated, then a dev checkout.
    static let modelsRoot: URL = {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("models", isDirectory: true)
        let dev = URL(filePath: "/Users/makar/dev/own-cotypist/models")
        return ModelInstallLocator.readRoot(
            bundledModels: bundled, installRoot: installRoot, devModels: dev)
    }()
    /// Fallback model when none is selected (best quality; the same family
    /// Cotypist runs).
    static let defaultModelName = "gemma-4-e4b-it-4bit"

    static func directory(for name: String) -> URL {
        modelsRoot.appendingPathComponent(name)
    }
    /// The currently selected model name (persisted), or the default — degraded
    /// to the first installed model when the preferred one isn't on disk (a DMG
    /// bundling a different model than the code default, or a deleted model), so
    /// a stale name can never leave the app silently suggestion-less.
    static var currentModelName: String {
        let preferred = SettingsStore.shared.state.global.selectedModel ?? defaultModelName
        let installed = ModelCatalog.availableModels(in: modelsRoot)
        if installed.contains(preferred) || installed.isEmpty { return preferred }
        return installed[0]
    }
    /// Absolute path to the selected model directory.
    static var modelDirectory: URL { directory(for: currentModelName) }

    /// Fixed decode budget. Where a suggestion actually STOPS is decided
    /// post-hoc by PhraseTrimmer; 40 tokens covers a half-sentence even in
    /// Ukrainian (~2-3.5 tokens per Cyrillic word).
    static let maxTokens = 40
    /// Raw-continuation context: the document tail fed to the model verbatim.
    /// Cheap in tokens (no chat template or few-shot overhead), so generous.
    static let promptMaxChars = 1500
    /// Idle time after the last keystroke before querying the LLM. Low for a
    /// snappy, eager feel — the suggestion chases the cursor instead of lagging.
    static let suggestionDebounceSeconds: Double = 0.09

    /// Online stops are CATASTROPHIC-only (a sub-2% token means the trajectory
    /// fell apart); quality decisions belong to the trimmer, which sees the
    /// whole trajectory. Dominance 1.0 disables the per-token branch-point gate
    /// that used to cut suggestions to 1-2 words.
    static let onlineFloor = ConfidenceThresholds(
        firstTokenMinProb: 0.02, minProb: 0.02, dominance: 1.0)

    /// Post-hoc trimming knobs. `firstTokenMinProb` is the show/no-show
    /// frequency dial (raw, unpenalized distribution — do not compare with the
    /// old penalized 0.10 gate); `lengthBonus` is effectively the "suggestion
    /// length" preference; `minMeanLogProb` is the garbage floor
    /// (-1.2 ≈ mean prob 0.30); `maxShownTokens` caps ghost-text length (user
    /// feedback 2026-07-03: full-budget suggestions read as a wall of text).
    /// Refine with `InklingBench compare/sweep`.
    static let trim = TrimConfig(
        firstTokenMinProb: 0.15, lengthBonus: 0.03, minMeanLogProb: -1.2,
        maxShownTokens: 16)
}
