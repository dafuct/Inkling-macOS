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
}
