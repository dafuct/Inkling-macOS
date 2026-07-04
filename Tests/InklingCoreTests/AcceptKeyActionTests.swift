import XCTest
@testable import InklingCore

final class AcceptKeyActionTests: XCTestCase {
    func test_notVisible_passThrough() {
        XCTAssertEqual(AcceptKeyAction.classify(
            isAcceptKey: true, optionHeld: false, suggestionVisible: false, alternativesAvailable: true), .passThrough)
    }
    func test_notAcceptKey_passThrough() {
        XCTAssertEqual(AcceptKeyAction.classify(
            isAcceptKey: false, optionHeld: false, suggestionVisible: true, alternativesAvailable: true), .passThrough)
    }
    func test_acceptKeyNoOption_accept() {
        XCTAssertEqual(AcceptKeyAction.classify(
            isAcceptKey: true, optionHeld: false, suggestionVisible: true, alternativesAvailable: true), .accept)
    }
    func test_optionWithAlternatives_cycle() {
        XCTAssertEqual(AcceptKeyAction.classify(
            isAcceptKey: true, optionHeld: true, suggestionVisible: true, alternativesAvailable: true), .cycle)
    }
    func test_optionNoAlternatives_passThrough() {
        XCTAssertEqual(AcceptKeyAction.classify(
            isAcceptKey: true, optionHeld: true, suggestionVisible: true, alternativesAvailable: false), .passThrough)
    }
}
