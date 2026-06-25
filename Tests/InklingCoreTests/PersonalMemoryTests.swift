import XCTest
@testable import InklingCore

final class PersonalMemoryTests: XCTestCase {
    func test_learn_incrementsWordCount() {
        let m = PersonalMemory()
        m.learn(word: "hello", previous: [])
        m.learn(word: "hello", previous: [])
        XCTAssertEqual(m.wordCounts["hello"], 2)
    }

    func test_wordCandidates_matchPrefixCaseInsensitively_sortedByCount() {
        let m = PersonalMemory()
        for _ in 0..<3 { m.learn(word: "Makarenko", previous: []) }
        m.learn(word: "Maker", previous: [])
        let cands = m.wordCandidates(withPrefix: "mak")
        XCTAssertEqual(cands.first?.word, "Makarenko")
        XCTAssertEqual(cands.first?.count, 3)
        XCTAssertEqual(cands.count, 2)   // both extend "mak"; the prefix itself is excluded
    }

    func test_wordCandidates_excludeExactPrefixMatch() {
        let m = PersonalMemory()
        m.learn(word: "the", previous: [])
        XCTAssertTrue(m.wordCandidates(withPrefix: "the").isEmpty)  // not longer than prefix
    }

    func test_learn_buildsBigramAndTrigram() {
        let m = PersonalMemory()
        m.learn(word: "you", previous: ["thank"])
        m.learn(word: "you", previous: ["I", "thank"])
        XCTAssertEqual(m.nextWordCandidates(after: ["thank"]).first?.word, "you")
        XCTAssertEqual(m.nextWordCandidates(after: ["I", "thank"]).first?.word, "you")
    }

    func test_nextWordCandidates_backsOffToBigram() {
        let m = PersonalMemory()
        m.learn(word: "world", previous: ["hello"])
        // Unknown trigram context falls back to the bigram on the last word.
        XCTAssertEqual(m.nextWordCandidates(after: ["random", "hello"]).first?.word, "world")
    }

    func test_decay_prunesRareWordsBelowFloor() {
        let m = PersonalMemory(limits: .init(decayFactor: 0.9, pruneFloor: 1.0))
        m.learn(word: "rare", previous: [])          // count 1.0
        for _ in 0..<5 { m.learn(word: "common", previous: []) }  // count 5.0
        m.decay()
        XCTAssertNil(m.wordCounts["rare"])            // 0.9 < 1.0 -> pruned
        XCTAssertEqual(m.wordCounts["common"] ?? 0, 4.5, accuracy: 0.0001)
    }

    func test_decay_capsToMaxWords_keepingHighestCounts() {
        let m = PersonalMemory(limits: .init(maxWords: 2, decayFactor: 1.0, pruneFloor: 0.0))
        m.learn(word: "a", previous: [])
        for _ in 0..<2 { m.learn(word: "b", previous: []) }
        for _ in 0..<3 { m.learn(word: "c", previous: []) }
        m.decay()
        XCTAssertNil(m.wordCounts["a"])               // lowest count dropped
        XCTAssertNotNil(m.wordCounts["b"])
        XCTAssertNotNil(m.wordCounts["c"])
    }
}
