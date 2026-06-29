import XCTest
@testable import InklingCore

final class SuggestionRepeatGuardTests: XCTestCase {
    // --- should FLAG (restatement / rephrase of recent text) -------------------

    func test_flags_rephraseOfRecentSentence() {
        // The screenshot case: typed "...is ready release soon", model rephrases.
        XCTAssertTrue(SuggestionRepeatGuard.repeatsRecent(
            continuation: "The release feature is ready",
            recentText: "The new feature is ready release soon"))
    }

    func test_flags_echoedPrefix() {
        XCTAssertTrue(SuggestionRepeatGuard.repeatsRecent(
            continuation: "the meeting is tomorrow",
            recentText: "Reminder: the meeting is tomorrow at"))
    }

    // --- should NOT flag (genuine continuations) -------------------------------

    func test_allows_shortCompletion() {
        // 2 words, below minWords -> never flagged even if both echo.
        XCTAssertFalse(SuggestionRepeatGuard.repeatsRecent(
            continuation: "is ready",
            recentText: "The new feature is ready"))
    }

    func test_allows_freshContinuation() {
        XCTAssertFalse(SuggestionRepeatGuard.repeatsRecent(
            continuation: "to ship to customers",
            recentText: "The new feature is ready"))
    }

    func test_allows_incidentalCommonWordOverlap() {
        // "think" overlaps but it's 1/4 of the continuation -> below threshold.
        XCTAssertFalse(SuggestionRepeatGuard.repeatsRecent(
            continuation: "think about it carefully",
            recentText: "honestly i think we should"))
    }

    func test_allows_emptyContinuation() {
        XCTAssertFalse(SuggestionRepeatGuard.repeatsRecent(
            continuation: "", recentText: "anything here"))
    }

    func test_allows_emptyRecentText() {
        XCTAssertFalse(SuggestionRepeatGuard.repeatsRecent(
            continuation: "the feature is ready", recentText: ""))
    }

    func test_distantRepetitionOutsideWindow_notFlagged() {
        // The repeated words sit far back, beyond the recent window.
        let filler = Array(repeating: "x", count: 30).joined(separator: " ")
        XCTAssertFalse(SuggestionRepeatGuard.repeatsRecent(
            continuation: "the feature is ready",
            recentText: "the feature is ready " + filler))
    }
}
