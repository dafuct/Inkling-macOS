import XCTest
@testable import InklingCore

final class AlternativeRingTests: XCTestCase {
    func test_empty() {
        var r = AlternativeRing([])
        XCTAssertNil(r.current)
        XCTAssertEqual(r.count, 0)
        XCTAssertFalse(r.hasAlternatives)
        r.next()                       // no-op
        XCTAssertNil(r.current)
    }

    func test_single_noAlternatives() {
        var r = AlternativeRing(["a"])
        XCTAssertEqual(r.current, "a")
        XCTAssertFalse(r.hasAlternatives)
        r.next()                       // stays
        XCTAssertEqual(r.current, "a")
    }

    func test_cycleWithWrap() {
        var r = AlternativeRing(["a", "b", "c"])
        XCTAssertTrue(r.hasAlternatives)
        XCTAssertEqual(r.current, "a")
        r.next(); XCTAssertEqual(r.current, "b")
        r.next(); XCTAssertEqual(r.current, "c")
        r.next(); XCTAssertEqual(r.current, "a")   // wrap
    }
}
