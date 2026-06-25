import XCTest
@testable import InklingCore

final class MemoryEngineTests: XCTestCase {
    private func memory(word: String, times: Int) -> PersonalMemory {
        let m = PersonalMemory()
        for _ in 0..<times { m.learn(word: word, previous: []) }
        return m
    }

    func test_completesDominantWord_returningSuffix() {
        let m = memory(word: "Makarenko", times: 3)
        let s = MemoryEngine.completion(currentWord: "Mak", precedingWords: [], memory: m)
        XCTAssertEqual(s, "arenko")
    }

    func test_silentBelowMinSightings() {
        let m = memory(word: "Makarenko", times: 2)   // < 3
        XCTAssertNil(MemoryEngine.completion(currentWord: "Mak", precedingWords: [], memory: m))
    }

    func test_silentBelowMinPrefixLength() {
        let m = memory(word: "Makarenko", times: 5)
        XCTAssertNil(MemoryEngine.completion(currentWord: "M", precedingWords: [], memory: m))
    }

    func test_silentWhenAmbiguous_noDominance() {
        let m = PersonalMemory()
        for _ in 0..<3 { m.learn(word: "Maker", previous: []) }
        for _ in 0..<3 { m.learn(word: "Makarenko", previous: []) }   // tie -> not dominant
        XCTAssertNil(MemoryEngine.completion(currentWord: "Mak", precedingWords: [], memory: m))
    }

    func test_firesWhenDominant() {
        let m = PersonalMemory()
        for _ in 0..<6 { m.learn(word: "Makarenko", previous: []) }   // 6
        for _ in 0..<2 { m.learn(word: "Maker", previous: []) }       // 2; 6 >= 2*2
        XCTAssertEqual(MemoryEngine.completion(currentWord: "Mak", precedingWords: [], memory: m), "arenko")
    }

    func test_predictsNextWords_byChaining() {
        let m = PersonalMemory()
        for _ in 0..<3 { m.learn(word: "Dmytro", previous: ["regards"]) }
        for _ in 0..<3 { m.learn(word: "Makarenko", previous: ["regards", "Dmytro"]) }
        let s = MemoryEngine.completion(currentWord: "", precedingWords: ["regards"], memory: m)
        XCTAssertEqual(s, "Dmytro Makarenko")
    }

    func test_nextWord_silentWhenNoContext() {
        let m = memory(word: "Dmytro", times: 5)
        XCTAssertNil(MemoryEngine.completion(currentWord: "", precedingWords: [], memory: m))
    }
}
