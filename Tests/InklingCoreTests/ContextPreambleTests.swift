import XCTest
@testable import InklingCore

final class ContextPreambleTests: XCTestCase {
    func test_neitherReturnsNil() {
        XCTAssertNil(ContextPreamble.build(.empty, tailLength: 10))
        XCTAssertNil(ContextPreamble.build(
            PromptContext(instructions: "", clipboard: "", screen: ""), tailLength: 10))
    }

    func test_instructionsOnly_matchesInstructionPreamble() {
        let combined = ContextPreamble.build(PromptContext(instructions: "Bob"), tailLength: 10)
        XCTAssertEqual(combined, InstructionPreamble.build(instructions: "Bob", tailLength: 10))
        XCTAssertEqual(combined, "Bob\n\n")
    }

    func test_clipboardOnly_hasSeparator() {
        XCTAssertEqual(ContextPreamble.build(PromptContext(clipboard: "hello world"), tailLength: 10),
                       "hello world\n\n")
    }

    func test_screenOnly_hasSeparator() {
        XCTAssertEqual(ContextPreamble.build(PromptContext(screen: "on screen"), tailLength: 10),
                       "on screen\n\n")
    }

    func test_instructionsAndClipboard_matchesG1Order() {
        XCTAssertEqual(
            ContextPreamble.build(PromptContext(instructions: "Bob", clipboard: "clip"), tailLength: 10),
            "Bob\n\nclip\n\n")
    }

    func test_allThreeInOrder() {
        XCTAssertEqual(
            ContextPreamble.build(
                PromptContext(instructions: "Bob", clipboard: "clip", screen: "scr"), tailLength: 10),
            "Bob\n\nclip\n\nscr\n\n")
    }

    func test_longTailReturnsNil() {
        XCTAssertNil(ContextPreamble.build(
            PromptContext(instructions: "Bob", clipboard: "clip", screen: "scr"), tailLength: 500))
    }
}
