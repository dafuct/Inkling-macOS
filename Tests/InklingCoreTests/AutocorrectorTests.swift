import XCTest
@testable import InklingCore

private struct FakeChecker: SpellChecker {
    let map: [String: String]
    func correction(for word: String) -> String? { map[word] }
}

final class AutocorrectorTests: XCTestCase {
    private func make(_ map: [String: String], real: Set<String> = []) -> Autocorrector {
        Autocorrector(checker: FakeChecker(map: map),
                      isRealWord: { real.contains($0.lowercased()) })
    }

    func test_correctsSimpleTypo() {
        let a = make(["teh": "the"])
        XCTAssertEqual(a.correction(for: "teh", memory: PersonalMemory()),
                       Correction(original: "teh", replacement: "the"))
    }

    func test_transfersTitleCase() {
        let a = make(["teh": "the"])
        XCTAssertEqual(a.correction(for: "Teh", memory: PersonalMemory())?.replacement, "The")
    }

    func test_transfersUpperCase() {
        let a = make(["teh": "the"])
        XCTAssertEqual(a.correction(for: "TEH", memory: PersonalMemory())?.replacement, "THE")
    }

    func test_skipsShortWords() {
        let a = make(["te": "be"])
        XCTAssertNil(a.correction(for: "te", memory: PersonalMemory()))
    }

    func test_skipsRealDictionaryWord() {
        let a = make(["form": "from"], real: ["form"])
        XCTAssertNil(a.correction(for: "form", memory: PersonalMemory()))
    }

    func test_skipsLearnedWord() {
        let mem = PersonalMemory()
        mem.learn(word: "debounce", previous: [])
        let a = make(["debounce": "denounce"])
        XCTAssertNil(a.correction(for: "debounce", memory: mem))
    }

    func test_skipsWhenNoCandidate() {
        let a = make([:])
        XCTAssertNil(a.correction(for: "hello", memory: PersonalMemory()))
    }

    func test_skipsIdentity() {
        let a = make(["hello": "hello"])
        XCTAssertNil(a.correction(for: "hello", memory: PersonalMemory()))
    }

    func test_rejectsFarEdit() {
        let a = make(["cat": "elephant"])
        XCTAssertNil(a.correction(for: "cat", memory: PersonalMemory()))
    }
}
