import Foundation
import InklingCore
import Observation

extension Notification.Name {
    /// Posted after `state.global.selectedModel` changes from the settings
    /// window, so AppDelegate reloads the engine.
    static let inklingModelChanged = Notification.Name("InklingModelChanged")
    /// Posted by the Personalization pane's "Delete All" to wipe typing history.
    static let inklingClearLearnedData = Notification.Name("InklingClearLearnedData")
}

/// Single source of truth for app settings. Main-thread only — the event tap,
/// the menu, and SwiftUI all run on the main run loop. Persists to JSON under
/// Application Support with a debounced atomic save (same pattern as
/// MemoryStore).
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    var state: SettingsState {
        didSet { scheduleSave() }
    }

    @ObservationIgnored private let url: URL
    @ObservationIgnored private var saveTimer: Timer?

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Inkling", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("settings.json")

        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(SettingsState.self, from: data) {
            state = decoded
        } else {
            state = Self.migrateFromUserDefaults()
            // Assigning `state` here happens inside init, so the `didSet`
            // observer does NOT fire and scheduleSave() is never triggered.
            // migrateFromUserDefaults() already deleted the legacy
            // UserDefaults keys, so if this launch exits before some other
            // mutation schedules a save, the migrated settings would be lost
            // permanently. Persist them to disk now, in this launch.
            saveNow()
        }
    }

    /// First launch after the upgrade: import the legacy keys, then remove
    /// them so this runs exactly once.
    private static func migrateFromUserDefaults() -> SettingsState {
        let d = UserDefaults.standard
        let state = SettingsMigration.fromLegacy(
            enabled: d.object(forKey: "InklingEnabled") as? Bool,
            selectedModel: d.string(forKey: "InklingSelectedModel"),
            learningEnabled: d.object(forKey: "InklingLearningEnabled") as? Bool)
        d.removeObject(forKey: "InklingEnabled")
        d.removeObject(forKey: "InklingSelectedModel")
        d.removeObject(forKey: "InklingLearningEnabled")
        return state
    }

    private func scheduleSave() {
        saveTimer?.invalidate()
        // 2s debounce, intentionally shorter than MemoryStore's 5s: settings
        // are low-volume writes and more latency-sensitive to persist.
        saveTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTimer?.invalidate()
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Bump the per-app counter behind the App Settings list. Unknown app
    /// (nil bundle ID) is not recorded.
    func recordSuggestionShown(bundleID: String?, appName: String?) {
        guard let bundleID else { return }
        var usage = state.appUsage[bundleID]
            ?? AppUsageInfo(displayName: appName ?? bundleID, lastSeen: Date())
        usage.suggestionsShown += 1
        usage.lastSeen = Date()
        if let appName { usage.displayName = appName }
        state.appUsage[bundleID] = usage
    }
}
