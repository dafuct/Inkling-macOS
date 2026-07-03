import CryptoKit
import Foundation
import InklingCore
import Observation

/// Encrypted, bounded on-disk store of captured typing inputs. Canonical
/// personalization record; PersonalMemory is rebuilt from it. Main-thread only,
/// debounced atomic write (MemoryStore pattern). Observable so the settings UI
/// can show a live count.
@Observable
final class InputStore {
    static let shared = InputStore()

    private(set) var records: [InputRecord]

    @ObservationIgnored private let url: URL
    @ObservationIgnored private let key = KeychainKey.getOrCreate()
    @ObservationIgnored private var saveTimer: Timer?
    @ObservationIgnored private let cap = 5_000

    var count: Int { records.count }

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Inkling", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("inputs.dat")
        records = Self.load(url: url, key: key)
    }

    func allRecords() -> [InputRecord] { records }

    func append(_ record: InputRecord) {
        records.append(record)
        if records.count > cap {
            let overflow = records.count - cap
            records.removeFirst(overflow)
            NSLog("Inkling: input store evicted \(overflow) oldest record(s) (cap \(cap))")
        }
        scheduleSave()
    }

    func deleteAll() {
        records = []
        saveTimer?.invalidate()
        try? FileManager.default.removeItem(at: url)
    }

    private static func load(url: URL, key: SymmetricKey) -> [InputRecord] {
        guard let blob = try? Data(contentsOf: url) else { return [] }
        do {
            let json = try CryptoBox.open(blob, key: key)
            return try JSONDecoder().decode([InputRecord].self, from: json)
        } catch {
            NSLog("Inkling: input store decrypt/decode failed (\(error)); starting empty")
            return []
        }
    }

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTimer?.invalidate()
        guard let json = try? JSONEncoder().encode(records),
              let blob = try? CryptoBox.seal(json, key: key) else { return }
        try? blob.write(to: url, options: .atomic)
    }
}
