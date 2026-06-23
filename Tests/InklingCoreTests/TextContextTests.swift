import XCTest
@testable import InklingCore

final class TextContextTests: XCTestCase {
    func test_prefix_returnsTextBeforeCaret() {
        let c = TextContext(fullText: "hello world", caretIndex: 5)
        XCTAssertEqual(c.prefix, "hello")
    }

    func test_currentWord_returnsPartialWordBeforeCaret() {
        let c = TextContext(fullText: "the quick bro", caretIndex: 13)
        XCTAssertEqual(c.currentWord, "bro")
    }

    func test_currentWord_isEmptyImmediatelyAfterSpace() {
        let c = TextContext(fullText: "hello ", caretIndex: 6)
        XCTAssertEqual(c.currentWord, "")
    }

    func test_caretIndex_isClampedToValidRange() {
        let c = TextContext(fullText: "hi", caretIndex: 999)
        XCTAssertEqual(c.prefix, "hi")
    }
}
