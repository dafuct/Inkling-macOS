import XCTest
@testable import InklingCore

final class SuggestionSyncTests: XCTestCase {
    func test_exactMatch_consistent() {
        XCTAssertTrue(SuggestionSync.consistent(recorded: "ver", live: "ver"))
    }

    func test_recorderAheadByInFlightKey_consistent() {
        // tap recorded "ver"; AX field still reads "ve" (app hasn't inserted "r")
        XCTAssertTrue(SuggestionSync.consistent(recorded: "ver", live: "ve"))
    }

    func test_recorderBehind_rejected() {
        // recorder missed a key; field is ahead -> don't trust recorder's suffix
        XCTAssertFalse(SuggestionSync.consistent(recorded: "ve", live: "ver"))
    }

    func test_diverged_rejected() {
        XCTAssertFalse(SuggestionSync.consistent(recorded: "ver", live: "veX"))
    }

    func test_bothEmpty_consistent() {
        // next-word prediction: both at a word boundary
        XCTAssertTrue(SuggestionSync.consistent(recorded: "", live: ""))
    }

    func test_recordedWordButLiveEmpty_rejected() {
        // mismatch on boundary: don't complete a word when the field has none
        XCTAssertFalse(SuggestionSync.consistent(recorded: "ver", live: ""))
    }

    func test_emptyRecordedButLiveWord_rejected() {
        XCTAssertFalse(SuggestionSync.consistent(recorded: "", live: "ver"))
    }
}
