import XCTest
@testable import InklingCore

final class MemoryEngineAlternativesTests: XCTestCase {
    private func memory(words: [(String, Int)] = [], bigrams: [(String, String, Int)] = []) -> PersonalMemory {
        let m = PersonalMemory()
        for (w, n) in words { for _ in 0..<n { m.learn(word: w, previous: []) } }
        for (prev, next, n) in bigrams { for _ in 0..<n { m.learn(word: next, previous: [prev]) } }
        return m
    }
    private let gates = MemoryEngine.Gates(minSightings: 3, minPrefixLength: 2, dominanceRatio: 2.0)

    func test_wordCompletion_rankedSuffixes_noDominanceRequired() {
        // "impl" prefix: implement(5), implementation(4) — NOT dominant, but both
        // clear minSightings; hit() would suppress, alternatives surfaces both.
        let m = memory(words: [("implement", 5), ("implementation", 4)])
        let alts = MemoryEngine.alternatives(
            currentWord: "impl", precedingWords: [], memory: m, gates: gates, max: 3)
        XCTAssertEqual(alts, ["ement", "ementation"])
    }

    func test_minSightingsFloorExcludesLowCount() {
        let m = memory(words: [("implement", 5), ("implode", 2)])   // implode below floor 3
        let alts = MemoryEngine.alternatives(
            currentWord: "impl", precedingWords: [], memory: m, gates: gates, max: 3)
        XCTAssertEqual(alts, ["ement"])
    }

    func test_cappedAtMax() {
        let m = memory(words: [("aaa", 6), ("aab", 5), ("aac", 4), ("aad", 3)])
        let alts = MemoryEngine.alternatives(
            currentWord: "aa", precedingWords: [], memory: m, gates: gates, max: 3)
        XCTAssertEqual(alts, ["a", "b", "c"])
    }

    func test_nextWord_singleStepCandidates() {
        // After "the": quick(5), lazy(4). Alternatives are single next-words.
        let m = memory(bigrams: [("the", "quick", 5), ("the", "lazy", 4)])
        let alts = MemoryEngine.alternatives(
            currentWord: "", precedingWords: ["the"], memory: m, gates: gates, max: 3)
        XCTAssertEqual(alts, ["quick", "lazy"])
    }

    func test_tooShortPrefixReturnsEmpty() {
        let m = memory(words: [("implement", 5)])
        XCTAssertTrue(MemoryEngine.alternatives(
            currentWord: "i", precedingWords: [], memory: m, gates: gates, max: 3).isEmpty)
    }

    func test_noCandidatesReturnsEmpty() {
        XCTAssertTrue(MemoryEngine.alternatives(
            currentWord: "zzz", precedingWords: [], memory: PersonalMemory(), gates: gates, max: 3).isEmpty)
    }
}
