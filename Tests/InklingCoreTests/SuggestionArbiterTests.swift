import XCTest
@testable import InklingCore

final class SuggestionArbiterTests: XCTestCase {
    func test_accepting_alwaysKeeps() {
        XCTAssertEqual(
            SuggestionArbiter.decide(shown: .llm, visibleText: "foo",
                                     llmSuggestion: "bar", accepting: true),
            .keep)
    }

    func test_exactMemoryRepeat_beatsLLM() {
        XCTAssertEqual(
            SuggestionArbiter.decide(shown: .memory(exactRepeat: true), visibleText: "arenko",
                                     llmSuggestion: "ovich", accepting: false),
            .keep)
    }

    func test_speculativeMemory_isUpgradedByLLM() {
        XCTAssertEqual(
            SuggestionArbiter.decide(shown: .memory(exactRepeat: false), visibleText: "Dmytro",
                                     llmSuggestion: "regards", accepting: false),
            .replaceWithLLM)
    }

    func test_emptyLLM_keepsShownMemory() {
        XCTAssertEqual(
            SuggestionArbiter.decide(shown: .memory(exactRepeat: false), visibleText: "Dmytro",
                                     llmSuggestion: "", accepting: false),
            .keep)
    }

    func test_emptyLLM_dismissesWhenNothingShown() {
        XCTAssertEqual(
            SuggestionArbiter.decide(shown: .none, visibleText: "",
                                     llmSuggestion: "", accepting: false),
            .dismiss)
    }

    func test_identicalLLM_isNoOp() {
        XCTAssertEqual(
            SuggestionArbiter.decide(shown: .llm, visibleText: "thread.",
                                     llmSuggestion: "thread.", accepting: false),
            .keep)
    }

    func test_differentLLM_replacesWhenNothingShown() {
        XCTAssertEqual(
            SuggestionArbiter.decide(shown: .none, visibleText: "",
                                     llmSuggestion: "thread.", accepting: false),
            .replaceWithLLM)
    }

    func test_differentLLM_upgradesAShownLLM() {
        // A later LLM result that differs from the one already shown replaces it.
        XCTAssertEqual(
            SuggestionArbiter.decide(shown: .llm, visibleText: "thread.",
                                     llmSuggestion: "queue.", accepting: false),
            .replaceWithLLM)
    }

    func test_emptyLLM_dismissesWhenLLMShown() {
        XCTAssertEqual(
            SuggestionArbiter.decide(shown: .llm, visibleText: "thread.",
                                     llmSuggestion: "", accepting: false),
            .dismiss)
    }

    func test_exactRepeat_beatsEmptyLLM() {
        XCTAssertEqual(
            SuggestionArbiter.decide(shown: .memory(exactRepeat: true), visibleText: "arenko",
                                     llmSuggestion: "", accepting: false),
            .keep)
    }
}
