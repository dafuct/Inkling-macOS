import XCTest
@testable import InklingCore

final class InputRecordTests: XCTestCase {
    func test_roundTrip_preservesFields() throws {
        let rec = InputRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000AB")!,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            appBundleID: "com.apple.TextEdit",
            text: "hello there",
            hadAcceptedCompletion: true)
        let data = try JSONEncoder().encode(rec)
        let decoded = try JSONDecoder().decode(InputRecord.self, from: data)
        XCTAssertEqual(decoded, rec)
    }

    func test_decodingMissingOptionalBundleID_isNil() throws {
        let json = #"{"id":"00000000-0000-0000-0000-0000000000AB","timestamp":0,"text":"hi","hadAcceptedCompletion":false}"#
        let decoded = try JSONDecoder().decode(InputRecord.self, from: Data(json.utf8))
        XCTAssertNil(decoded.appBundleID)
        XCTAssertEqual(decoded.text, "hi")
        XCTAssertFalse(decoded.hadAcceptedCompletion)
    }
}
