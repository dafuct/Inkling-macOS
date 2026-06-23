import XCTest
@testable import InklingCore

final class SuggestionEngineTests: XCTestCase {
    func test_dummyEngine_suggestsAfterNonEmptyPrefix() {
        let engine = DummyEngine()
        let ctx = TextContext(fullText: "hel", caretIndex: 3)
        XCTAssertEqual(engine.suggestion(for: ctx), " hello")
    }

    func test_dummyEngine_returnsEmptyForEmptyPrefix() {
        let engine = DummyEngine()
        let ctx = TextContext(fullText: "", caretIndex: 0)
        XCTAssertEqual(engine.suggestion(for: ctx), "")
    }
}
