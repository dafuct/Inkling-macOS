import XCTest
@testable import InklingCore

final class SettingsModelTests: XCTestCase {
    func test_roundTrip_preservesState() throws {
        var state = SettingsState()
        state.global.enabled = false
        state.global.selectedModel = "gemma-4-e4b-it-4bit"
        state.perApp["com.apple.TextEdit"] = AppOverrides(
            completions: .off, midLine: .on, autocorrect: .useDefault,
            disableAcceptKey: .on, improveCompatibility: true,
            customInstructions: "Formal tone.")
        state.appUsage["com.apple.TextEdit"] = AppUsageInfo(
            displayName: "TextEdit", suggestionsShown: 42,
            lastSeen: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(SettingsState.self, from: data)
        XCTAssertEqual(decoded, state)
    }

    func test_decodingEmptyObject_yieldsDefaults() throws {
        let decoded = try JSONDecoder().decode(SettingsState.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, SettingsState())
        XCTAssertTrue(decoded.global.enabled)
        XCTAssertTrue(decoded.global.collectInputs)
        XCTAssertTrue(decoded.global.storeWithoutAccepted)
        XCTAssertEqual(decoded.global.personalizeLevel, 1)
        XCTAssertEqual(decoded.global.customInstructions, "")
        XCTAssertFalse(decoded.global.instructionPreambleEnabled)
        XCTAssertFalse(decoded.global.midLineEnabled)
        XCTAssertTrue(decoded.global.autocorrectEnabled)
        XCTAssertFalse(decoded.global.disableAcceptKeyDefault)
        XCTAssertEqual(decoded.version, 1)
    }

    func test_decodingGlobalInstructions_roundTrips() throws {
        let json = #"{"global":{"customInstructions":"Be terse.","instructionPreambleEnabled":true}}"#
        let decoded = try JSONDecoder().decode(SettingsState.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.global.customInstructions, "Be terse.")
        XCTAssertTrue(decoded.global.instructionPreambleEnabled)
    }

    func test_decodingLegacyLearningEnabled_mapsToCollectInputs() throws {
        let json = #"{"global":{"learningEnabled":false}}"#
        let decoded = try JSONDecoder().decode(SettingsState.self, from: Data(json.utf8))
        XCTAssertFalse(decoded.global.collectInputs)
    }

    func test_decodingCollectInputs_takesPrecedenceOverLegacy() throws {
        let json = #"{"global":{"collectInputs":true,"learningEnabled":false}}"#
        let decoded = try JSONDecoder().decode(SettingsState.self, from: Data(json.utf8))
        XCTAssertTrue(decoded.global.collectInputs)
    }

    func test_encoding_neverWritesLegacyLearningEnabledKey() throws {
        let data = try JSONEncoder().encode(SettingsState())
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("learningEnabled"))
        XCTAssertTrue(json.contains("collectInputs"))
    }

    func test_decodingPartialOverrides_fillsDefaults() throws {
        let json = #"{"perApp":{"com.example":{"completions":"off"}}}"#
        let decoded = try JSONDecoder().decode(SettingsState.self, from: Data(json.utf8))
        let overrides = decoded.perApp["com.example"]
        XCTAssertEqual(overrides?.completions, .off)
        XCTAssertEqual(overrides?.midLine, .useDefault)
        XCTAssertEqual(overrides?.disableAcceptKey, .useDefault)
        XCTAssertEqual(overrides?.improveCompatibility, false)
        XCTAssertEqual(overrides?.customInstructions, "")
    }

    func test_decodingPartialUsageEntry_fillsDefaults() throws {
        let json = #"{"appUsage":{"com.example":{"suggestionsShown":7}}}"#
        let decoded = try JSONDecoder().decode(SettingsState.self, from: Data(json.utf8))
        let usage = decoded.appUsage["com.example"]
        XCTAssertEqual(usage?.suggestionsShown, 7)
        XCTAssertEqual(usage?.displayName, "")
        XCTAssertEqual(usage?.lastSeen, Date(timeIntervalSince1970: 0))
    }

    func test_overrideChoice_resolvesAgainstDefault() {
        XCTAssertTrue(OverrideChoice.useDefault.resolved(default: true))
        XCTAssertFalse(OverrideChoice.useDefault.resolved(default: false))
        XCTAssertTrue(OverrideChoice.on.resolved(default: false))
        XCTAssertFalse(OverrideChoice.off.resolved(default: true))
    }

    func test_useClipboardContext_defaultsFalse() {
        XCTAssertFalse(GlobalSettings().useClipboardContext)
    }

    func test_useClipboardContext_roundTrips() throws {
        var g = GlobalSettings()
        g.useClipboardContext = true
        let data = try JSONEncoder().encode(g)
        let decoded = try JSONDecoder().decode(GlobalSettings.self, from: data)
        XCTAssertTrue(decoded.useClipboardContext)
    }

    func test_useScreenContext_defaultsFalse() {
        XCTAssertFalse(GlobalSettings().useScreenContext)
    }

    func test_useScreenContext_roundTrips() throws {
        var g = GlobalSettings()
        g.useScreenContext = true
        let data = try JSONEncoder().encode(g)
        let decoded = try JSONDecoder().decode(GlobalSettings.self, from: data)
        XCTAssertTrue(decoded.useScreenContext)
    }

    func test_showAlternatives_defaultsFalse() {
        XCTAssertFalse(GlobalSettings().showAlternatives)
    }

    func test_showAlternatives_roundTrips() throws {
        var g = GlobalSettings()
        g.showAlternatives = true
        let data = try JSONEncoder().encode(g)
        let decoded = try JSONDecoder().decode(GlobalSettings.self, from: data)
        XCTAssertTrue(decoded.showAlternatives)
    }

    func test_appsSortedByUsage_ordersByCountThenName() {
        var state = SettingsState()
        let t = Date(timeIntervalSince1970: 0)
        state.appUsage["b.low"] = AppUsageInfo(displayName: "Beta", suggestionsShown: 1, lastSeen: t)
        state.appUsage["a.high"] = AppUsageInfo(displayName: "Alpha", suggestionsShown: 9, lastSeen: t)
        state.appUsage["c.tie"] = AppUsageInfo(displayName: "Aardvark", suggestionsShown: 1, lastSeen: t)
        XCTAssertEqual(state.appsSortedByUsage().map(\.bundleID), ["a.high", "c.tie", "b.low"])
    }
}
