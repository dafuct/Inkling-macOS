import XCTest
@testable import InklingCore

final class MemoryGatePresetTests: XCTestCase {
    func test_levelZero_disablesMemoryTier() {
        XCTAssertNil(MemoryEngine.gates(forLevel: 0))
        XCTAssertNil(MemoryEngine.gates(forLevel: -5))   // clamps to 0
    }

    func test_levelOne_isConservative() {
        let g = MemoryEngine.gates(forLevel: 1)
        XCTAssertEqual(g?.minSightings, 3)
        XCTAssertEqual(g?.dominanceRatio, 2.0)
        XCTAssertEqual(g?.minPrefixLength, 2)
        XCTAssertEqual(g?.maxChainWords, 3)
    }

    func test_maxLevel_isMostEager() {
        let g = MemoryEngine.gates(forLevel: MemoryEngine.maxPersonalizationLevel)
        XCTAssertEqual(g?.minSightings, 1)
        XCTAssertEqual(g?.dominanceRatio, 1.1)
    }

    func test_aboveMax_clampsToMax() {
        XCTAssertEqual(MemoryEngine.gates(forLevel: 99)?.minSightings,
                       MemoryEngine.gates(forLevel: MemoryEngine.maxPersonalizationLevel)?.minSightings)
    }

    func test_gatesAreMonotonicNonIncreasing() {
        var prevSight = Double.infinity
        var prevDom = Double.infinity
        for level in 1...MemoryEngine.maxPersonalizationLevel {
            let g = MemoryEngine.gates(forLevel: level)!
            XCTAssertLessThanOrEqual(g.minSightings, prevSight)
            XCTAssertLessThanOrEqual(g.dominanceRatio, prevDom)
            prevSight = g.minSightings
            prevDom = g.dominanceRatio
        }
    }
}
