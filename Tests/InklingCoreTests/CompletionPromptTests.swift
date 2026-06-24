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

    func test_inline_stripsRestatedWord() {
        // caret after "h", model restates "how are you" -> insert "ow are you"
        XCTAssertEqual(
            CompletionPrompt.inlineSuggestion(
                continuation: "how are you", currentWord: "h",
                currentWordIsComplete: false, prefixEndsWithSpace: false),
            "ow are you")
    }

    func test_inline_partialWordSuffixNoSpace() {
        XCTAssertEqual(
            CompletionPrompt.inlineSuggestion(
                continuation: "p me", currentWord: "hel",
                currentWordIsComplete: false, prefixEndsWithSpace: false),
            "p me")
    }

    func test_inline_completeWordAddsSpace() {
        XCTAssertEqual(
            CompletionPrompt.inlineSuggestion(
                continuation: "park", currentWord: "the",
                currentWordIsComplete: true, prefixEndsWithSpace: false),
            " park")
    }

    func test_inline_afterSpaceNoExtraSpace() {
        XCTAssertEqual(
            CompletionPrompt.inlineSuggestion(
                continuation: "library", currentWord: "",
                currentWordIsComplete: false, prefixEndsWithSpace: true),
            "library")
    }

    func test_inline_emptyStaysEmpty() {
        XCTAssertEqual(
            CompletionPrompt.inlineSuggestion(
                continuation: "", currentWord: "x",
                currentWordIsComplete: false, prefixEndsWithSpace: false),
            "")
    }
}
