import XCTest
@testable import InklingCore

final class SuggestionEngineTests: XCTestCase {
    func test_dummyEngine_completesCurrentWordInline() async {
        let engine = DummyEngine()
        let ctx = TextContext(fullText: "hel", caretIndex: 3)
        let result = await engine.suggestion(for: ctx)
        XCTAssertEqual(result, "lo")   // hel -> hello
    }

    func test_dummyEngine_completesDifferentPrefixes() async {
        let engine = DummyEngine()
        let ctx = TextContext(fullText: "I live in a ho", caretIndex: 14)
        let result = await engine.suggestion(for: ctx)
        XCTAssertEqual(result, "use")  // ho -> house
    }

    func test_dummyEngine_returnsEmptyWhenNoPartialWord() async {
        let engine = DummyEngine()
        let ctx = TextContext(fullText: "hello ", caretIndex: 6)  // currentWord ""
        let result = await engine.suggestion(for: ctx)
        XCTAssertEqual(result, "")
    }

    func test_dummyEngine_returnsEmptyWhenNoMatch() async {
        let engine = DummyEngine()
        let ctx = TextContext(fullText: "xq", caretIndex: 2)
        let result = await engine.suggestion(for: ctx)
        XCTAssertEqual(result, "")
    }

    func test_dummyEngine_returnsEmptyWhenWordAlreadyComplete() async {
        let engine = DummyEngine()
        let ctx = TextContext(fullText: "hello", caretIndex: 5)  // exact match, no suffix
        let result = await engine.suggestion(for: ctx)
        XCTAssertEqual(result, "")
    }
}
