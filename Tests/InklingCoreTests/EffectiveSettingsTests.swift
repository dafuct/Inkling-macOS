import XCTest
@testable import InklingCore

final class EffectiveSettingsTests: XCTestCase {
    private func state(
        enabled: Bool = true,
        overrides: [String: AppOverrides] = [:]
    ) -> SettingsState {
        var s = SettingsState()
        s.global.enabled = enabled
        s.perApp = overrides
        return s
    }

    // MARK: completions

    func test_completions_defaultOn() {
        XCTAssertTrue(EffectiveSettings.completionsEnabled(state: state(), bundleID: "com.example"))
    }

    func test_completions_nilBundleID_usesGlobal() {
        XCTAssertTrue(EffectiveSettings.completionsEnabled(state: state(), bundleID: nil))
        XCTAssertFalse(EffectiveSettings.completionsEnabled(state: state(enabled: false), bundleID: nil))
    }

    func test_completions_perAppOff_beatsGlobalOn() {
        let s = state(overrides: ["com.example": AppOverrides(completions: .off)])
        XCTAssertFalse(EffectiveSettings.completionsEnabled(state: s, bundleID: "com.example"))
        XCTAssertTrue(EffectiveSettings.completionsEnabled(state: s, bundleID: "com.other"))
    }

    func test_completions_masterSwitchBeatsPerAppOn() {
        let s = state(enabled: false, overrides: ["com.example": AppOverrides(completions: .on)])
        XCTAssertFalse(EffectiveSettings.completionsEnabled(state: s, bundleID: "com.example"))
    }

    // MARK: accept key

    func test_acceptKey_enabledByDefault() {
        XCTAssertTrue(EffectiveSettings.acceptKeyEnabled(state: state(), bundleID: "com.example"))
    }

    func test_acceptKey_perAppDisable() {
        let s = state(overrides: ["com.example": AppOverrides(disableAcceptKey: .on)])
        XCTAssertFalse(EffectiveSettings.acceptKeyEnabled(state: s, bundleID: "com.example"))
        XCTAssertTrue(EffectiveSettings.acceptKeyEnabled(state: s, bundleID: "com.other"))
    }

    func test_acceptKey_globalDefaultDisabled_perAppReEnables() {
        var s = state(overrides: ["com.example": AppOverrides(disableAcceptKey: .off)])
        s.global.disableAcceptKeyDefault = true
        XCTAssertTrue(EffectiveSettings.acceptKeyEnabled(state: s, bundleID: "com.example"))
        XCTAssertFalse(EffectiveSettings.acceptKeyEnabled(state: s, bundleID: "com.other"))
    }

    // MARK: mid-line / autocorrect (consumers arrive in E/F; resolution is live now)

    func test_midLine_followsGlobalDefault() {
        var s = state()
        XCTAssertFalse(EffectiveSettings.midLineEnabled(state: s, bundleID: "com.example"))
        s.global.midLineEnabled = true
        XCTAssertTrue(EffectiveSettings.midLineEnabled(state: s, bundleID: "com.example"))
    }

    func test_midLine_perAppOverrideWins() {
        let s = state(overrides: ["com.example": AppOverrides(midLine: .on)])
        XCTAssertTrue(EffectiveSettings.midLineEnabled(state: s, bundleID: "com.example"))
    }

    func test_autocorrect_perAppOffBeatsGlobalOnDefault() {
        let s = state(overrides: ["com.example": AppOverrides(autocorrect: .off)])
        XCTAssertFalse(EffectiveSettings.autocorrectEnabled(state: s, bundleID: "com.example"))
        XCTAssertTrue(EffectiveSettings.autocorrectEnabled(state: s, bundleID: "com.other"))
    }

    // MARK: custom instructions / compatibility

    func test_customInstructions_bothBlank_isNil() {
        let s = state(overrides: ["com.example": AppOverrides(customInstructions: "   \n")])
        XCTAssertNil(EffectiveSettings.customInstructions(state: s, bundleID: "com.example"))
        XCTAssertNil(EffectiveSettings.customInstructions(state: s, bundleID: nil))
        XCTAssertNil(EffectiveSettings.customInstructions(state: s, bundleID: "com.other"))
    }

    func test_customInstructions_perAppOnly() {
        let s = state(overrides: ["com.example": AppOverrides(customInstructions: " Be brief. ")])
        XCTAssertEqual(
            EffectiveSettings.customInstructions(state: s, bundleID: "com.example"), "Be brief.")
    }

    func test_customInstructions_globalOnly() {
        var s = state()
        s.global.customInstructions = " Write formally. "
        XCTAssertEqual(
            EffectiveSettings.customInstructions(state: s, bundleID: "com.other"), "Write formally.")
        XCTAssertEqual(
            EffectiveSettings.customInstructions(state: s, bundleID: nil), "Write formally.")
    }

    func test_customInstructions_globalAndPerApp_combinedInOrder() {
        var s = state(overrides: ["com.example": AppOverrides(customInstructions: "Use bullet points.")])
        s.global.customInstructions = "Write formally."
        XCTAssertEqual(
            EffectiveSettings.customInstructions(state: s, bundleID: "com.example"),
            "Write formally.\n\nUse bullet points.")
    }

    func test_improveCompatibility_defaultsFalse() {
        XCTAssertFalse(EffectiveSettings.improveCompatibility(state: state(), bundleID: "com.example"))
        let s = state(overrides: ["com.example": AppOverrides(improveCompatibility: true)])
        XCTAssertTrue(EffectiveSettings.improveCompatibility(state: s, bundleID: "com.example"))
    }

    // MARK: clipboard context

    func test_clipboardContext_globalDefaultOffByDefault() {
        XCTAssertFalse(EffectiveSettings.clipboardContextEnabled(state: state(), bundleID: "com.example"))
    }

    func test_clipboardContext_perAppOnBeatsGlobalOff() {
        let s = state(overrides: ["com.example": AppOverrides(clipboardContext: .on)])
        XCTAssertTrue(EffectiveSettings.clipboardContextEnabled(state: s, bundleID: "com.example"))
        XCTAssertFalse(EffectiveSettings.clipboardContextEnabled(state: s, bundleID: "com.other"))
    }
}
