import XCTest
@testable import InklingCore

final class CompletionEventTests: XCTestCase {
    func test_roundTrip_preservesFields() throws {
        let e = CompletionEvent(timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                                appBundleID: "com.apple.TextEdit", words: 1, chars: 6,
                                isFirstChunk: true)
        let decoded = try JSONDecoder().decode(CompletionEvent.self,
                                               from: JSONEncoder().encode(e))
        XCTAssertEqual(decoded, e)
    }

    func test_decodingMissingFields_useDefaults() throws {
        let json = #"{"timestamp":0,"chars":4}"#
        let d = try JSONDecoder().decode(CompletionEvent.self, from: Data(json.utf8))
        XCTAssertNil(d.appBundleID)
        XCTAssertEqual(d.words, 0)
        XCTAssertEqual(d.chars, 4)
        XCTAssertFalse(d.isFirstChunk)
    }

    func test_enums_areCaseIterable() {
        XCTAssertEqual(StatsMetric.allCases.count, 3)
        XCTAssertEqual(StatsGroupBy.allCases.count, 3)
        XCTAssertEqual(StatsRange.allCases.count, 5)
    }
}
