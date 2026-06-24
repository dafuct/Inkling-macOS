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

    func test_spaced_addsSpaceBetweenWords() {
        XCTAssertEqual(CompletionPrompt.spaced(continuation: "library", afterWordChar: true), " library")
    }

    func test_spaced_noSpaceWhenNotAfterWord() {
        XCTAssertEqual(CompletionPrompt.spaced(continuation: "library", afterWordChar: false), "library")
    }

    func test_spaced_noSpaceWhenContinuationStartsNonWord() {
        XCTAssertEqual(CompletionPrompt.spaced(continuation: ".com", afterWordChar: true), ".com")
    }
}
