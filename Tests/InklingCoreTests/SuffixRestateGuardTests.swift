import XCTest
@testable import InklingCore

final class SuffixRestateGuardTests: XCTestCase {
    func test_restates_whenContinuationReproducesSuffixOpening() {
        XCTAssertTrue(SuffixRestateGuard.restates(
            continuation: "the mat and looked around", suffix: "the mat"))
    }

    func test_restates_evenWhenContinuationAddsMuchMore() {
        // Reproduces "foo bar" then diverges + adds lots — a fraction formula
        // would dilute this below threshold; the leading run still catches it.
        XCTAssertTrue(SuffixRestateGuard.restates(
            continuation: "foo bar something entirely different here now", suffix: "foo bar qux"))
    }

    func test_notRestate_forGenuineForwardContinuation() {
        // Shares only the leading stopword "the"; run breaks at cat != dog.
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
