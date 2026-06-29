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
        // caret after "hel", model restates "help me with something" -> "p me ..."
        // (restatement wins regardless of completeness).
        XCTAssertEqual(
            CompletionPrompt.inlineSuggestion(
                continuation: "help me with something", currentWord: "hel",
                prefixEndsWithSpace: false, currentWordIsComplete: false),
            "p me with something")
    }

    func test_inline_restatedWord_caseInsensitive() {
        XCTAssertEqual(
            CompletionPrompt.inlineSuggestion(
                continuation: "how are you", currentWord: "h",
                prefixEndsWithSpace: false, currentWordIsComplete: false),
            "ow are you")
    }

    func test_inline_partialWord_glues() {
        // "contri" is not a complete word -> the continuation completes it, no
        // space: "contri"+"bute to the project" = "contribute to the project".
        XCTAssertEqual(
            CompletionPrompt.inlineSuggestion(
                continuation: "bute to the project", currentWord: "contri",
                prefixEndsWithSpace: false, currentWordIsComplete: false),
            "bute to the project")
    }

    func test_inline_completeWord_getsSpace() {
        // "ready" is a complete word -> the continuation is a NEW word, space-
        // separated: "ready"+"release soon" = "ready release soon".
        XCTAssertEqual(
            CompletionPrompt.inlineSuggestion(
                continuation: "release soon", currentWord: "ready",
                prefixEndsWithSpace: false, currentWordIsComplete: true),
            " release soon")
    }

    func test_inline_newWordAfterSpace_insertedAsIs() {
        XCTAssertEqual(
            CompletionPrompt.inlineSuggestion(
                continuation: "library", currentWord: "",
                prefixEndsWithSpace: true, currentWordIsComplete: false),
            "library")
    }

    func test_inline_newWordAfterPunctuation_getsSpace() {
        XCTAssertEqual(
            CompletionPrompt.inlineSuggestion(
                continuation: "and then", currentWord: "",
                prefixEndsWithSpace: false, currentWordIsComplete: false),
            " and then")
    }

    func test_inline_emptyStaysEmpty() {
        XCTAssertEqual(
            CompletionPrompt.inlineSuggestion(
                continuation: "", currentWord: "x",
                prefixEndsWithSpace: false, currentWordIsComplete: true),
            "")
    }
}
