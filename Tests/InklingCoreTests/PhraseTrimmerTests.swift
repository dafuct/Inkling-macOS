import XCTest
@testable import InklingCore

final class PhraseTrimmerTests: XCTestCase {
    /// Builds cumulative prefixes from token pieces, the shape GatedDecoder emits.
    private func prefixes(_ pieces: [String]) -> [String] {
        var acc = ""
        return pieces.map { acc += $0; return acc }
    }

    private let loose = TrimConfig(firstTokenMinProb: 0.1, lengthBonus: 0.04, minMeanLogProb: -2.0)

    func test_cutsAtSentenceEnd_notMidWord() {
        // "... dog." then a weak continuation; budget-stopped (not natural end).
        let p = prefixes([" jumps", " over", " the", " lazy", " dog", ".", " May"])
        let probs = [0.9, 0.8, 0.9, 0.7, 0.8, 0.9, 0.2]
        let out = PhraseTrimmer.trim(prefixes: p, probs: probs, endedNaturally: false, config: loose)
        XCTAssertEqual(out, " jumps over the lazy dog.")
    }

    func test_neverCutsInsideWord_onBudgetStop() {
        // Budget ran out mid-word ("unfin"); the cut retreats to the last boundary.
        let p = prefixes([" ready", " for", " review", " unfin"])
        let probs = [0.8, 0.7, 0.8, 0.6]
        let out = PhraseTrimmer.trim(prefixes: p, probs: probs, endedNaturally: false, config: loose)
        XCTAssertEqual(out, " ready for review")
    }

    func test_naturalEnd_allowsFinalToken() {
        let p = prefixes(["bute", " later"])   // completes "contri|" then EOS
        let out = PhraseTrimmer.trim(
            prefixes: p, probs: [0.8, 0.9], endedNaturally: true, config: loose)
        XCTAssertEqual(out, "bute later")
    }

    func test_singleMidWordToken_withoutNaturalEnd_showsNothing() {
        let out = PhraseTrimmer.trim(
            prefixes: ["bute"], probs: [0.8], endedNaturally: false, config: loose)
        XCTAssertEqual(out, "")
    }

    func test_firstTokenFloor_suppresses() {
        let p = prefixes([" maybe", " something"])
        let out = PhraseTrimmer.trim(
            prefixes: p, probs: [0.05, 0.9], endedNaturally: true,
            config: TrimConfig(firstTokenMinProb: 0.15, lengthBonus: 0.04, minMeanLogProb: -2.0))
        XCTAssertEqual(out, "")
    }

    func test_garbageFloor_suppresses() {
        // All tokens weak: mean log prob below the floor -> nothing shown.
        let p = prefixes([" this", " that", " other"])
        let out = PhraseTrimmer.trim(
            prefixes: p, probs: [0.2, 0.1, 0.1], endedNaturally: true,
            config: TrimConfig(firstTokenMinProb: 0.1, lengthBonus: 0.0, minMeanLogProb: -1.2))
        XCTAssertEqual(out, "")
    }

    func test_lengthBonus_prefersLongerPhrase() {
        // Confident half-sentence beats a slightly-more-confident single word.
        let p = prefixes([" and", " then", " we", " ship", " it", "."])
        let probs = [0.9, 0.6, 0.6, 0.55, 0.6, 0.7]
        let out = PhraseTrimmer.trim(
            prefixes: p, probs: probs, endedNaturally: false,
            config: TrimConfig(firstTokenMinProb: 0.1, lengthBonus: 0.08, minMeanLogProb: -2.0))
        XCTAssertEqual(out, " and then we ship it.")
    }

    func test_preservesLeadingSpace_trimsTrailingWhitespace() {
        let p = prefixes([" questions", " "])
        let out = PhraseTrimmer.trim(
            prefixes: p, probs: [0.8, 0.5], endedNaturally: true, config: loose)
        XCTAssertEqual(out, " questions")
    }

    func test_ukrainianText_cutsOnWordBoundary() {
        let p = prefixes([" пи", "тан", "ня", " до", " релізу", " зав"])
        let probs = [0.8, 0.9, 0.9, 0.8, 0.85, 0.3]
        let out = PhraseTrimmer.trim(prefixes: p, probs: probs, endedNaturally: false, config: loose)
        XCTAssertEqual(out, " питання до релізу")
    }

    func test_emptyInput_showsNothing() {
        XCTAssertEqual(PhraseTrimmer.trim(prefixes: [], probs: [], endedNaturally: true), "")
    }

    func test_maxShownTokens_capsLength_evenWhenAllConfident() {
        // 24 confident single-word tokens; cap 4 -> at most 4 tokens survive.
        let pieces = (0..<24).map { " w\($0)" }
        let p = prefixes(pieces)
        let probs = Array(repeating: 0.9, count: 24)
        let out = PhraseTrimmer.trim(
            prefixes: p, probs: probs, endedNaturally: false,
            config: TrimConfig(
                firstTokenMinProb: 0.1, lengthBonus: 0.5, minMeanLogProb: -2.0,
                maxShownTokens: 4))
        XCTAssertEqual(out, " w0 w1 w2 w3")
    }
}
