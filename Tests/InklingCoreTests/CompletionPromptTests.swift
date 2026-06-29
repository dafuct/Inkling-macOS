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

    func test_inline_restatedWord_stripsToSuffix() {
        // caret after "hel", model restates "help me with something" -> "p me with something"
        XCTAssertEqual(
            CompletionPrompt.inlineSuggestion(
                continuation: "help me with something", currentWord: "hel",
                prefixEndsWithSpace: false),
            "p me with something")
    }

    func test_inline_restatedWord_caseInsensitive() {
        // caret after "h", model restates "how are you" -> "ow are you"
        XCTAssertEqual(
            CompletionPrompt.inlineSuggestion(
                continuation: "how are you", currentWord: "h", prefixEndsWithSpace: false),
            "ow are you")
    }

    func test_inline_newWordAfterCompleteWord_getsSpace() {
        // caret right after a complete word "ready" (no trailing space); the model
        // continues with a NEW word -> space-separate, never "readyrelease".
        XCTAssertEqual(
            CompletionPrompt.inlineSuggestion(
                continuation: "release soon", currentWord: "ready", prefixEndsWithSpace: false),
            " release soon")
    }

    func test_inline_newWordAfterSpace_insertedAsIs() {
        XCTAssertEqual(
            CompletionPrompt.inlineSuggestion(
                continuation: "library", currentWord: "", prefixEndsWithSpace: true),
            "library")
    }

    func test_inline_newWordAfterPunctuation_getsSpace() {
        XCTAssertEqual(
            CompletionPrompt.inlineSuggestion(
                continuation: "and then", currentWord: "", prefixEndsWithSpace: false),
            " and then")
    }

    func test_inline_emptyStaysEmpty() {
        XCTAssertEqual(
            CompletionPrompt.inlineSuggestion(
                continuation: "", currentWord: "x", prefixEndsWithSpace: false),
            "")
    }
}
