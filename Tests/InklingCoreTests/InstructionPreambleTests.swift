import XCTest
@testable import InklingCore

final class InstructionPreambleTests: XCTestCase {
    func test_blankInstructions_isNil() {
        XCTAssertNil(InstructionPreamble.build(instructions: "   \n", tailLength: 10))
    }

    func test_longTail_isNil() {
        XCTAssertNil(InstructionPreamble.build(
            instructions: "Be terse.", tailLength: InstructionPreamble.shortTailThreshold))
    }

    func test_shortTail_returnsPreambleWithSeparator() {
        let p = InstructionPreamble.build(instructions: " Be terse. ", tailLength: 10)
        XCTAssertEqual(p, "Be terse.\n\n")
    }

    func test_overCap_truncatesAtWordBoundary() {
        let long = String(repeating: "word ", count: 100)   // 500 chars
        let p = InstructionPreamble.build(instructions: long, tailLength: 10)!
        let body = p.replacingOccurrences(of: "\n\n", with: "")
        XCTAssertLessThanOrEqual(body.count, InstructionPreamble.maxChars)
        XCTAssertFalse(body.hasSuffix("wor"))   // never cut mid-word
        XCTAssertTrue(body.hasSuffix("word"))
    }

    func test_overCap_noWhitespace_hardCuts() {
        let long = String(repeating: "x", count: 500)
        let p = InstructionPreamble.build(instructions: long, tailLength: 10)!
        let body = p.replacingOccurrences(of: "\n\n", with: "")
        XCTAssertEqual(body.count, InstructionPreamble.maxChars)
    }

    // Documents the echo-suppression reuse: a continuation that repeats the
    // preamble's content words is caught by the existing guard with a wide window.
    func test_preambleEcho_isCaughtByRepeatGuard() {
        let preamble = "Write formally about quarterly financial projections."
        let echo = "quarterly financial projections summary"
        XCTAssertTrue(SuggestionRepeatGuard.repeatsRecent(
            continuation: echo, recentText: preamble, recentWindow: 100))
    }
}
