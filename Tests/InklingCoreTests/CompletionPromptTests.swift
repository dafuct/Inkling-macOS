import XCTest
@testable import InklingCore

final class CompletionPromptTests: XCTestCase {
    func test_prompt_isTrailingContext() {
        let ctx = TextContext(fullText: "I was thinking we sho", caretIndex: 21)
        XCTAssertEqual(CompletionPrompt.prompt(for: ctx, maxChars: 100), "I was thinking we sho")
    }

    func test_prompt_truncatedToMaxChars() {
        let ctx = TextContext(fullText: "abcdefghij", caretIndex: 10)
        XCTAssertEqual(CompletionPrompt.prompt(for: ctx, maxChars: 4), "ghij")
    }

    func test_clean_firstLineTrimmedUnquoted() {
        XCTAssertEqual(CompletionPrompt.clean("\"library.\"\nand then"), "library.")
    }

    func test_clean_trimsWhitespace() {
        XCTAssertEqual(CompletionPrompt.clean("  hello there  "), "hello there")
    }

    func test_clean_empty() {
        XCTAssertEqual(CompletionPrompt.clean(""), "")
    }

    func test_inline_midWordCompletesNoSpace() {
        XCTAssertEqual(
            CompletionPrompt.inlineSuggestion(continuation: "p me", midWord: true, prefixEndsWithSpace: false),
            "p me")
    }

    func test_inline_newWordAddsSpace() {
        XCTAssertEqual(
            CompletionPrompt.inlineSuggestion(continuation: "library", midWord: false, prefixEndsWithSpace: false),
            " library")
    }

    func test_inline_newWordAfterSpaceNoExtraSpace() {
        XCTAssertEqual(
            CompletionPrompt.inlineSuggestion(continuation: "library", midWord: false, prefixEndsWithSpace: true),
            "library")
    }

    func test_inline_emptyStaysEmpty() {
        XCTAssertEqual(
            CompletionPrompt.inlineSuggestion(continuation: "", midWord: false, prefixEndsWithSpace: false),
            "")
    }
}
