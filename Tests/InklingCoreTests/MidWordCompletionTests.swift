import XCTest
@testable import InklingCore

final class MidWordCompletionTests: XCTestCase {
    // --- decodePrompt ----------------------------------------------------------

    func test_decodePrompt_dropsPartialWord() {
        XCTAssertEqual(
            MidWordCompletion.decodePrompt(prefix: "I need to impl", currentWord: "impl"),
            "I need to ")
    }

    func test_decodePrompt_identifierFragment() {
        XCTAssertEqual(
            MidWordCompletion.decodePrompt(
                prefix: "by calling loadModelContai", currentWord: "loadModelContai"),
            "by calling ")
    }

    func test_decodePrompt_noWord_returnsPrefixUnchanged() {
        XCTAssertEqual(
            MidWordCompletion.decodePrompt(prefix: "ready to go ", currentWord: ""),
            "ready to go ")
    }

    // --- resolve ---------------------------------------------------------------

    func test_resolve_matchWithLeadingSpace_returnsSuffix() {
        XCTAssertEqual(
            MidWordCompletion.resolve(candidate: " implement the parser", currentWord: "impl"),
            "ement the parser")
    }

    func test_resolve_matchWithoutLeadingSpace_returnsSuffix() {
        XCTAssertEqual(
            MidWordCompletion.resolve(candidate: "implementation details", currentWord: "impl"),
            "ementation details")
    }

    func test_resolve_caseInsensitive_preservesModelTail() {
        XCTAssertEqual(
            MidWordCompletion.resolve(candidate: " Implement it", currentWord: "impl"),
            "ement it")
    }

    func test_resolve_differentWord_returnsNil() {
        XCTAssertNil(
            MidWordCompletion.resolve(candidate: " Trait for a function", currentWord: "impl"))
    }

    func test_resolve_exactWordOnly_returnsEmptySuffix() {
        XCTAssertEqual(
            MidWordCompletion.resolve(candidate: " impl", currentWord: "impl"), "")
    }

    func test_resolve_ukrainian() {
        XCTAssertEqual(
            MidWordCompletion.resolve(candidate: " питання до релізу", currentWord: "пита"),
            "ння до релізу")
    }
}
