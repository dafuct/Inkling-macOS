import Foundation
import InklingCore
import Observation

/// Plaintext, bounded, observable store of accepted-completion events for the
/// Statistics screen. Events hold only counts/timestamps/bundle IDs (no typed
/// text), so — unlike InputStore — this is not encrypted. Main-thread only,
/// debounced atomic save (MemoryStore pattern).
@Observable
final class CompletionEventStore {
    static let shared = CompletionEventStore()

    private(set) var events: [CompletionEvent]

    @ObservationIgnored private let url: URL
    @ObservationIgnored private var saveTimer: Timer?
    @ObservationIgnored private let cap = 100_000
    @ObservationIgnored private let retentionDays = 365

    var count: Int { events.count }

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Inkling", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("stats.json")
        events = Self.load(url: url)
        let trimmed = Self.trim(events, cap: cap, retentionDays: retentionDays, now: Date())
        if trimmed.count != events.count {
            NSLog("Inkling: stats store trimmed \(events.count - trimmed.count) old/overflow event(s)")
            events = trimmed
        }
    }

    func allEvents() -> [CompletionEvent] { events }

    func record(_ event: CompletionEvent) {
        events.append(event)
        if events.count > cap { events.removeFirst(events.count - cap) }
        scheduleSave()
    }

    private static func load(url: URL) -> [CompletionEvent] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        do { return try JSONDecoder().decode([CompletionEvent].self, from: data) }
        catch { NSLog("Inkling: stats decode failed (\(error)); starting empty"); return [] }
    }

    /// Drop events older than `retentionDays` and, if still over `cap`, keep newest.
    static func trim(_ events: [CompletionEvent], cap: Int, retentionDays: Int, now: Date) -> [CompletionEvent] {
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        var kept = events.filter { $0.timestamp >= cutoff }
        if kept.count > cap { kept.removeFirst(kept.count - cap) }
        return kept
    }

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTimer?.invalidate()
        guard let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
