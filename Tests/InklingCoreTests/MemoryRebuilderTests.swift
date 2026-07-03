import XCTest
@testable import InklingCore

final class MemoryRebuilderTests: XCTestCase {
    private func record(_ text: String) -> InputRecord {
        InputRecord(id: UUID(), timestamp: Date(timeIntervalSince1970: 0),
                    appBundleID: nil, text: text, hadAcceptedCompletion: false)
    }

    func test_rebuild_matchesLiveLearningForSameText() {
        let text = "the quick brown fox the quick"
        // Live path: feed the text through a recorder, flush the trailing word.
        let live = PersonalMemory()
        let recorder = MemoryRecorder()
        recorder.onWord = { word, prev in live.learn(word: word, previous: prev) }
        recorder.append(text)
        recorder.flush()
        // Rebuild path: single record with the same text.
        let rebuilt = PersonalMemory()
        MemoryRebuilder.rebuild(from: [record(text)], into: rebuilt)
        XCTAssertEqual(rebuilt.snapshot.wordCounts, live.snapshot.wordCounts)
        XCTAssertEqual(rebuilt.snapshot.bigrams, live.snapshot.bigrams)
        XCTAssertEqual(rebuilt.snapshot.trigrams, live.snapshot.trigrams)
    }

    func test_rebuild_countsRepeatsAcrossRecords() {
        let mem = PersonalMemory()
        MemoryRebuilder.rebuild(from: [record("hello world"), record("hello there")], into: mem)
        XCTAssertEqual(mem.snapshot.wordCounts["hello"], 2)
        XCTAssertEqual(mem.snapshot.wordCounts["world"], 1)
    }

    func test_rebuild_resetsContextBetweenRecords() {
        // "world" then a new record starting "hello" must NOT create a
        // world->hello bigram: an input boundary breaks n-gram context.
        let mem = PersonalMemory()
        MemoryRebuilder.rebuild(from: [record("hello world"), record("hello there")], into: mem)
        XCTAssertNil(mem.snapshot.bigrams["world"]?["hello"])
        XCTAssertEqual(mem.snapshot.bigrams["hello"]?["world"], 1)
        XCTAssertEqual(mem.snapshot.bigrams["hello"]?["there"], 1)
    }
}
