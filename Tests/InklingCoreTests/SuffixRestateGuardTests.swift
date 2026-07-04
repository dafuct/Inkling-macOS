import XCTest
@testable import InklingCore

final class SuffixRestateGuardTests: XCTestCase {
    func test_restates_whenContinuationRepeatsSuffixStart() {
        XCTAssertTrue(SuffixRestateGuard.restates(
            continuation: "the mat and looked around", suffix: "the mat"))
    }

    func test_notRestate_forGenuineForwardContinuation() {
        // Shares only the stopword "the" with the suffix.
        XCTAssertFalse(SuffixRestateGuard.restates(
            continuation: "the cat ran off", suffix: "the dog barked"))
    }

    func test_notRestate_whenSuffixEmpty() {
        XCTAssertFalse(SuffixRestateGuard.restates(continuation: "anything here", suffix: ""))
    }

    func test_notRestate_whenContinuationEmpty() {
        XCTAssertFalse(SuffixRestateGuard.restates(continuation: "", suffix: "the mat"))
    }

    func test_restates_isCaseInsensitive() {
        XCTAssertTrue(SuffixRestateGuard.restates(
            continuation: "The Mat is soft", suffix: "the mat"))
    }
}
