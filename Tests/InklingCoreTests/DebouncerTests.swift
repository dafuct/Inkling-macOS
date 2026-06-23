import XCTest
@testable import InklingCore

final class DebouncerTests: XCTestCase {
    func test_onlyLastScheduledActionRuns_whenCalledRapidly() {
        let debouncer = Debouncer(delay: 0.05)
        var runs = 0
        let exp = expectation(description: "fires once")
        for _ in 0..<5 { debouncer.schedule { runs += 1; exp.fulfill() } }
        wait(for: [exp], timeout: 1.0)
        let settle = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { settle.fulfill() }
        wait(for: [settle], timeout: 1.0)
        XCTAssertEqual(runs, 1)
    }

    func test_cancel_preventsScheduledAction() {
        let debouncer = Debouncer(delay: 0.05)
        var ran = false
        debouncer.schedule { ran = true }
        debouncer.cancel()
        let settle = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { settle.fulfill() }
        wait(for: [settle], timeout: 1.0)
        XCTAssertFalse(ran)
    }
}
