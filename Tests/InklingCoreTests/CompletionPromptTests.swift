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

    func test_inline_nonRestatementMidWord_suppressed_partialWord() {
        // Typing "contri" mid-word; the model gives a continuation that does NOT
        // restate it. We cannot tell a completion ("contri"+"bute"="contribute",
        // wants glue) from a new word ("ready"+"release", wants a space) from the
        // strings, and both guesses produce garbage in the wrong case ("contri
        // bute" / "readyrelease"). Suppress: mid-word completion arrives via the
        // restatement branch below and the deterministic memory tier.
        XCTAssertEqual(
            CompletionPrompt.inlineSuggestion(
                continuation: "bute to the project", currentWord: "contri",
                prefixEndsWithSpace: false),
            "")
    }

    func test_inline_nonRestatementMidWord_suppressed_completeWord() {
        // The other half of the same ambiguity: caret after a complete word with
        // no trailing space. Also suppressed (a continuation arrives once the user
        // types the separating space -> currentWord empty -> shown).
        XCTAssertEqual(
            CompletionPrompt.inlineSuggestion(
                continuation: "release soon", currentWord: "ready", prefixEndsWithSpace: false),
            "")
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
