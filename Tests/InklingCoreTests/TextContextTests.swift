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

    func test_lineSuffix_midLine_returnsRestOfLine() {
        let c = TextContext(fullText: "the cat sat on the mat", caretIndex: 15)  // after "the cat sat on "
        XCTAssertEqual(c.lineSuffix, "the mat")
    }

    func test_lineSuffix_atLineEnd_isEmpty() {
        let c = TextContext(fullText: "hello world", caretIndex: 11)
        XCTAssertEqual(c.lineSuffix, "")
    }

    func test_lineSuffix_stopsAtNewline() {
        let c = TextContext(fullText: "abc def\nghi", caretIndex: 3)  // after "abc"
        XCTAssertEqual(c.lineSuffix, " def")
    }

    func test_lineSuffix_caretBeforeNewline_isEmpty() {
        let c = TextContext(fullText: "abc\ndef", caretIndex: 3)  // right before "\n"
        XCTAssertEqual(c.lineSuffix, "")
    }
}
