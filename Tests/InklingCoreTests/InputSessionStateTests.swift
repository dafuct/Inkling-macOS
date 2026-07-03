import XCTest
@testable import InklingCore

final class InputSessionStateTests: XCTestCase {
    func test_trivialText_isNotStored() {
        let s = InputSessionState()
        XCTAssertFalse(s.shouldStore(text: "", storeWithoutAccepted: true))
        XCTAssertFalse(s.shouldStore(text: "  \n ", storeWithoutAccepted: true))
        XCTAssertFalse(s.shouldStore(text: "hi", storeWithoutAccepted: true))   // 2 chars
    }

    func test_nonTrivialText_storedWhenStoreWithoutAcceptedTrue() {
        let s = InputSessionState()
        XCTAssertTrue(s.shouldStore(text: "hey", storeWithoutAccepted: true))
    }

    func test_storeWithoutAcceptedFalse_requiresAcceptance() {
        var s = InputSessionState()
        XCTAssertFalse(s.shouldStore(text: "hello world", storeWithoutAccepted: false))
        s.noteAccepted()
        XCTAssertTrue(s.shouldStore(text: "hello world", storeWithoutAccepted: false))
    }

    func test_reset_clearsAcceptance() {
        var s = InputSessionState()
        s.noteAccepted()
        XCTAssertTrue(s.hadAcceptedCompletion)
        s.reset()
        XCTAssertFalse(s.hadAcceptedCompletion)
    }
}
