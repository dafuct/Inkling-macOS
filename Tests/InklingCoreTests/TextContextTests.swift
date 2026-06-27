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

    func test_isAtLineEnd_trueAtEndOfText() {
        XCTAssertTrue(TextContext(fullText: "hello", caretIndex: 5).isAtLineEnd)
    }

    func test_isAtLineEnd_trueWhenNextCharIsNewline() {
        XCTAssertTrue(TextContext(fullText: "hello\nworld", caretIndex: 5).isAtLineEnd)
    }

    func test_isAtLineEnd_falseWhenTextFollowsOnTheLine() {
        // Caret moved into the middle — a suggestion here would overlap "world".
        XCTAssertFalse(TextContext(fullText: "hello world", caretIndex: 5).isAtLineEnd)
    }

    func test_isAtLineEnd_falseMidWord() {
        XCTAssertFalse(TextContext(fullText: "make", caretIndex: 1).isAtLineEnd)
    }

    func test_isAtLineEnd_trueForEmptyText() {
        XCTAssertTrue(TextContext(fullText: "", caretIndex: 0).isAtLineEnd)
    }
}
