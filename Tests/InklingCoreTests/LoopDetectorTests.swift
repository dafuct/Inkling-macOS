import XCTest
@testable import InklingCore

final class LoopDetectorTests: XCTestCase {
    func test_tripleSameToken_isLoop() {
        XCTAssertTrue(LoopDetector.hasLoop([5, 9, 9, 9]))
    }

    func test_periodTwoLoop_isLoop() {
        // "Look at Look at Look at" as ids: 1 2 1 2 1 2 -> trigram (1,2,1) recurs at gap 2.
        XCTAssertTrue(LoopDetector.hasLoop([1, 2, 1, 2, 1, 2]))
    }

    func test_periodThreeLoop_isLoop() {
        XCTAssertTrue(LoopDetector.hasLoop([1, 2, 3, 1, 2, 3, 1]))
    }

    func test_cleanText_noLoop() {
        XCTAssertFalse(LoopDetector.hasLoop([10, 11, 12, 13, 14, 15, 16, 17]))
    }

    func test_distantLegitimateReuse_noLoop() {
        // "of the" (7,8) reused far apart across a clause — must NOT be flagged.
        XCTAssertFalse(LoopDetector.hasLoop([7, 8, 1, 2, 3, 4, 5, 6, 7, 8, 9]))
    }

    func test_doubleToken_notYetLoop() {
        XCTAssertFalse(LoopDetector.hasLoop([9, 9]))
    }

    func test_empty_noLoop() {
        XCTAssertFalse(LoopDetector.hasLoop([]))
    }
}
