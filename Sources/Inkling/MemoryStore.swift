import Foundation
import InklingCore

/// Persists a PersonalMemory to JSON under Application Support, with a debounced
/// save so frequent edits don't thrash the disk. Main-thread only.
final class MemoryStore {
    private let memory: PersonalMemory
    private let url: URL
    private var saveTimer: Timer?

    init(memory: PersonalMemory) {
        self.memory = memory
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Inkling", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("memory.json")
    }

    /// Load any saved model into `memory`. Safe to call once at launch.
    func load() {
        guard let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(PersonalMemory.Snapshot.self, from: data)
        else { return }
        memory.restore(from: snap)
    }

    /// Schedule a save ~5s after the most recent change.
    func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            self?.saveNow()
        }
    }

    func saveNow() {
        guard let data = try? JSONEncoder().encode(memory.snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Wipe the model and delete the file on disk.
    func clear() {
        memory.restore(from: PersonalMemory.Snapshot())
        saveTimer?.invalidate()
        try? FileManager.default.removeItem(at: url)
    }
}
