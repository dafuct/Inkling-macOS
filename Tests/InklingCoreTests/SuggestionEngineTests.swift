import XCTest
@testable import InklingCore

final class SuggestionEngineTests: XCTestCase {
    func test_dummyEngine_completesCurrentWordInline() {
        let engine = DummyEngine()
        let ctx = TextContext(fullText: "hel", caretIndex: 3)
        XCTAssertEqual(engine.suggestion(for: ctx), "lo")   // hel -> hello
    }

    func test_dummyEngine_completesDifferentPrefixes() {
        let engine = DummyEngine()
        let ctx = TextContext(fullText: "I live in a ho", caretIndex: 14)
        XCTAssertEqual(engine.suggestion(for: ctx), "use")  // ho -> house
    }

    func test_dummyEngine_returnsEmptyWhenNoPartialWord() {
        let engine = DummyEngine()
        let ctx = TextContext(fullText: "hello ", caretIndex: 6)  // currentWord ""
        XCTAssertEqual(engine.suggestion(for: ctx), "")
    }

    func test_dummyEngine_returnsEmptyWhenNoMatch() {
        let engine = DummyEngine()
        let ctx = TextContext(fullText: "xq", caretIndex: 2)
        XCTAssertEqual(engine.suggestion(for: ctx), "")
    }

    func test_dummyEngine_returnsEmptyWhenWordAlreadyComplete() {
        let engine = DummyEngine()
        let ctx = TextContext(fullText: "hello", caretIndex: 5)  // exact match, no suffix
        XCTAssertEqual(engine.suggestion(for: ctx), "")
    }
}
