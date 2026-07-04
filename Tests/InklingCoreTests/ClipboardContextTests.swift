import XCTest
@testable import InklingCore

final class ClipboardContextTests: XCTestCase {
    func test_shortTailReturnsTrimmedText() {
        XCTAssertEqual(ClipboardContext.build(clipboard: "  hello world  ", tailLength: 10),
                       "hello world")
    }

    func test_emptyReturnsNil() {
        XCTAssertNil(ClipboardContext.build(clipboard: "", tailLength: 10))
    }

    func test_whitespaceOnlyReturnsNil() {
        XCTAssertNil(ClipboardContext.build(clipboard: "   \n\t ", tailLength: 10))
    }

    func test_longTailReturnsNil() {
        XCTAssertNil(ClipboardContext.build(clipboard: "hello", tailLength: 400))
    }

    func test_capsToWordBoundary() {
        let long = String(repeating: "ab ", count: 200)   // ~600 chars, spaces every 3
        let out = ClipboardContext.build(clipboard: long, tailLength: 10)
        XCTAssertNotNil(out)
        XCTAssertLessThanOrEqual(out!.count, ClipboardContext.maxChars)
        XCTAssertFalse(out!.hasSuffix("a"))   // cut at a space, not mid-token
    }
}
