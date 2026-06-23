import XCTest
@testable import InklingCore

final class KeystrokeBufferTests: XCTestCase {
    func test_appendBuildsText() {
        let b = KeystrokeBuffer(); b.append("h"); b.append("i")
        XCTAssertEqual(b.text, "hi")
    }
    func test_backspaceRemovesLast() {
        let b = KeystrokeBuffer(); b.append("a"); b.append("b"); b.backspace()
        XCTAssertEqual(b.text, "a")
    }
    func test_backspaceOnEmptyIsSafe() {
        let b = KeystrokeBuffer(); b.backspace()
        XCTAssertEqual(b.text, "")
    }
    func test_resetClears() {
        let b = KeystrokeBuffer(); b.append("xyz"); b.reset()
        XCTAssertEqual(b.text, "")
    }
}
