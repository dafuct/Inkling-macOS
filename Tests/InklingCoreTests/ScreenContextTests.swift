import XCTest
@testable import InklingCore

final class ScreenContextTests: XCTestCase {
    func test_shortTailReturnsTrimmedText() {
        XCTAssertEqual(ScreenContext.build(screenText: "  invoice total  ", tailLength: 10),
                       "invoice total")
    }

    func test_emptyReturnsNil() {
        XCTAssertNil(ScreenContext.build(screenText: "", tailLength: 10))
    }

    func test_whitespaceOnlyReturnsNil() {
        XCTAssertNil(ScreenContext.build(screenText: "  \n\t ", tailLength: 10))
    }

    func test_longTailReturnsNil() {
        XCTAssertNil(ScreenContext.build(screenText: "on screen", tailLength: 400))
    }

    func test_capsToWordBoundary() {
        let long = String(repeating: "ab ", count: 200)
        let out = ScreenContext.build(screenText: long, tailLength: 10)
        XCTAssertNotNil(out)
        XCTAssertLessThanOrEqual(out!.count, ScreenContext.maxChars)
        XCTAssertFalse(out!.hasSuffix("a"))
    }
}
