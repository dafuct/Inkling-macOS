import XCTest
import CoreGraphics
@testable import InklingCore

final class CaretGeometryTests: XCTestCase {
    func test_prefersPrecedingCharTrailingEdge_overBogusWideAtCaretRect() {
        // Apple Notes (big element): the at-caret range returns a full-width
        // end-of-line fill rect; the preceding char is a normal glyph at the
        // real caret. Using the wide rect's maxX would fly to the right margin.
        let prev = CGRect(x: 577, y: 608, width: 7, height: 16)
        let wideAtCaret = CGRect(x: 584, y: 608, width: 1312, height: 16)
        let r = CaretGeometry.caretRect(prevChar: prev, atCaret: wideAtCaret, marker: nil)
        XCTAssertEqual(r, prev)
        XCTAssertEqual(r?.maxX ?? 0, 584, accuracy: 1)   // at the caret, not ~1896
    }

    func test_fallsBackToMarker_whenRangeBoundsAreDegenerate() {
        // Apple Notes (small element): range bounds are zero-size; the marker
        // insertion point is correct.
        let degenerate = CGRect(x: 0, y: 1080, width: 0, height: 0)
        let marker = CGRect(x: 684, y: 1006, width: 0, height: 18)
        let r = CaretGeometry.caretRect(prevChar: degenerate, atCaret: degenerate, marker: marker)
        XCTAssertEqual(r, marker)
    }

    func test_usesAtCaretLeadingEdgeCollapsed_atStartOfText() {
        // No preceding char (caret at index 0): use the leading edge of the char
        // at the caret, collapsed to zero width so maxX is the caret.
        let atCaret = CGRect(x: 100, y: 50, width: 8, height: 16)
        let r = CaretGeometry.caretRect(prevChar: nil, atCaret: atCaret, marker: nil)
        XCTAssertEqual(r?.maxX ?? -1, 100, accuracy: 0.001)   // leading edge, not 108
        XCTAssertEqual(r?.height ?? 0, 16, accuracy: 0.001)
        XCTAssertEqual(r?.width ?? -1, 0, accuracy: 0.001)
    }

    func test_prefersPrecedingChar_inPlainTextField() {
        // TextEdit at end-of-text: at-caret is nil, preceding char is the caret.
        let prev = CGRect(x: 200, y: 30, width: 9, height: 18)
        let r = CaretGeometry.caretRect(prevChar: prev, atCaret: nil, marker: nil)
        XCTAssertEqual(r, prev)
    }

    func test_returnsNil_whenNothingUsable() {
        let degenerate = CGRect(x: 0, y: 0, width: 0, height: 0)
        XCTAssertNil(CaretGeometry.caretRect(prevChar: degenerate, atCaret: nil, marker: nil))
    }
}
