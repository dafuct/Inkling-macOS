import XCTest
@testable import InklingCore

final class ConfidenceGateTests: XCTestCase {
    private let t = ConfidenceThresholds(firstTokenMinProb: 0.65, minProb: 0.45, dominance: 1.5)

    func test_emptyProbs_keepsNothing() {
        XCTAssertEqual(ConfidenceGate.acceptedTokenCount(probs: [], thresholds: t), 0)
    }

    func test_weakFirstToken_keepsNothing() {
        // 0.5 < firstTokenMinProb (0.65) -> silent, even though later tokens are strong
        let probs: [(top1: Double, top2: Double)] = [(0.5, 0.1), (0.9, 0.01)]
        XCTAssertEqual(ConfidenceGate.acceptedTokenCount(probs: probs, thresholds: t), 0)
    }

    func test_allConfident_keepsAll() {
        let probs: [(top1: Double, top2: Double)] = [(0.9, 0.02), (0.8, 0.05), (0.7, 0.10)]
        XCTAssertEqual(ConfidenceGate.acceptedTokenCount(probs: probs, thresholds: t), 3)
    }

    func test_confidenceDropsMidway_truncates() {
        // idx 2: 0.30 < minProb (0.45) -> keep first two
        let probs: [(top1: Double, top2: Double)] = [(0.9, 0.02), (0.7, 0.10), (0.30, 0.20)]
        XCTAssertEqual(ConfidenceGate.acceptedTokenCount(probs: probs, thresholds: t), 2)
    }

    func test_dominanceFailure_truncates() {
        // idx 1: 0.50 >= minProb but 0.50 < 1.5 * 0.40 (=0.60) -> fails dominance
        let probs: [(top1: Double, top2: Double)] = [(0.9, 0.02), (0.50, 0.40)]
        XCTAssertEqual(ConfidenceGate.acceptedTokenCount(probs: probs, thresholds: t), 1)
    }

    func test_zeroRunnerUp_disablesDominance() {
        XCTAssertTrue(ConfidenceGate.accepts(top1: 0.66, top2: 0, isFirst: true, thresholds: t))
    }

    func test_top2_returnsTwoHighest() {
        let r = ConfidenceGate.top2(of: [0.1, 0.7, 0.2, 0.05])
        XCTAssertEqual(r.top1, 0.7, accuracy: 1e-6)
        XCTAssertEqual(r.top2, 0.2, accuracy: 1e-6)
    }

    func test_top2_singleValue_secondIsZero() {
        let r = ConfidenceGate.top2(of: [0.9])
        XCTAssertEqual(r.top1, 0.9, accuracy: 1e-6)
        XCTAssertEqual(r.top2, 0.0, accuracy: 1e-6)
    }

    func test_subsequentToken_usesLowerFloor() {
        // 0.55 is below firstTokenMinProb (0.65) but above minProb (0.45):
        // rejected as the first token, accepted as a later token.
        XCTAssertFalse(ConfidenceGate.accepts(top1: 0.55, top2: 0.0, isFirst: true,  thresholds: t))
        XCTAssertTrue( ConfidenceGate.accepts(top1: 0.55, top2: 0.0, isFirst: false, thresholds: t))
    }

    func test_tiedTopTwo_failsDominance() {
        // top1 == top2 -> ratio 1.0 < dominance (1.5) -> rejected (coin-flip)
        XCTAssertFalse(ConfidenceGate.accepts(top1: 0.7, top2: 0.7, isFirst: false, thresholds: t))
    }

    func test_top2_empty_returnsZeroZero() {
        let r = ConfidenceGate.top2(of: [])
        XCTAssertEqual(r.top1, 0.0, accuracy: 1e-6)
        XCTAssertEqual(r.top2, 0.0, accuracy: 1e-6)
    }

    func test_eagerFloor_stillSilencesCoinFlipViaDominance() {
        let eager = ConfidenceThresholds(firstTokenMinProb: 0.10, minProb: 0.10, dominance: 1.5)
        // Coin-flip / post-repetition-penalty loop signature: clears the low floor
        // but fails dominance (0.30 < 1.5 * 0.28) -> rejected. Dominance is the floor.
        XCTAssertFalse(ConfidenceGate.accepts(top1: 0.30, top2: 0.28, isFirst: true, thresholds: eager))
        // A dominant low-probability best guess is now SHOWN (eager).
        XCTAssertTrue(ConfidenceGate.accepts(top1: 0.30, top2: 0.05, isFirst: true, thresholds: eager))
    }
}
