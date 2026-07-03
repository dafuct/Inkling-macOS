import Foundation

/// Rebuilds the derived PersonalMemory from the canonical input records.
/// Reuses MemoryRecorder so tokenization is identical to live learning; each
/// record is an independent context (a fresh recorder per record), because an
/// input boundary breaks n-gram context.
public enum MemoryRebuilder {
    public static func rebuild(from records: [InputRecord], into memory: PersonalMemory) {
        for record in records {
            let recorder = MemoryRecorder()
            recorder.onWord = { word, previous in memory.learn(word: word, previous: previous) }
            recorder.append(record.text)
            recorder.flush()
        }
    }
}
