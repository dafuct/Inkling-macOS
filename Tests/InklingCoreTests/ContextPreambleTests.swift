import XCTest
@testable import InklingCore

final class ContextPreambleTests: XCTestCase {
    func test_neitherReturnsNil() {
        XCTAssertNil(ContextPreamble.build(instructions: nil, clipboard: nil, tailLength: 10))
        XCTAssertNil(ContextPreamble.build(instructions: "", clipboard: "", tailLength: 10))
    }

    func test_instructionsOnly_matchesInstructionPreamble() {
        let combined = ContextPreamble.build(instructions: "Bob", clipboard: nil, tailLength: 10)
        XCTAssertEqual(combined, InstructionPreamble.build(instructions: "Bob", tailLength: 10))
        XCTAssertEqual(combined, "Bob\n\n")
    }

    func test_clipboardOnly_hasSeparator() {
        XCTAssertEqual(ContextPreamble.build(instructions: nil, clipboard: "hello world", tailLength: 10),
                       "hello world\n\n")
    }

    func test_bothInstructionsFirst() {
        XCTAssertEqual(ContextPreamble.build(instructions: "Bob", clipboard: "hello world", tailLength: 10),
                       "Bob\n\nhello world\n\n")
    }

    func test_longTailReturnsNil() {
        XCTAssertNil(ContextPreamble.build(instructions: "Bob", clipboard: "hello", tailLength: 500))
    }
}
