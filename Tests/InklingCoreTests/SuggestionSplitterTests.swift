import XCTest
@testable import InklingCore

final class SuggestionSplitterTests: XCTestCase {
    func test_splitsLeadingSpaceAndFirstWord() {
        let r = SuggestionSplitter.nextChunk(of: " hello world")
        XCTAssertEqual(r.chunk, " hello")
        XCTAssertEqual(r.remainder, " world")
    }
    func test_lastWordLeavesEmptyRemainder() {
        let r = SuggestionSplitter.nextChunk(of: " world")
        XCTAssertEqual(r.chunk, " world")
        XCTAssertEqual(r.remainder, "")
    }
    func test_noLeadingSpace() {
        let r = SuggestionSplitter.nextChunk(of: "hello there")
        XCTAssertEqual(r.chunk, "hello")
        XCTAssertEqual(r.remainder, " there")
    }
    func test_emptyString() {
        let r = SuggestionSplitter.nextChunk(of: "")
        XCTAssertEqual(r.chunk, "")
        XCTAssertEqual(r.remainder, "")
    }
}
