import XCTest
@testable import InklingCore

final class SettingsMigrationTests: XCTestCase {
    func test_allLegacyKeysPresent_areImported() {
        let s = SettingsMigration.fromLegacy(
            enabled: false, selectedModel: "gemma-4-e4b-it-4bit", learningEnabled: false)
        XCTAssertFalse(s.global.enabled)
        XCTAssertEqual(s.global.selectedModel, "gemma-4-e4b-it-4bit")
        XCTAssertFalse(s.global.collectInputs)
        XCTAssertTrue(s.perApp.isEmpty)
        XCTAssertTrue(s.appUsage.isEmpty)
    }

    func test_absentLegacyKeys_useDefaults() {
        let s = SettingsMigration.fromLegacy(enabled: nil, selectedModel: nil, learningEnabled: nil)
        XCTAssertEqual(s, SettingsState())
        XCTAssertTrue(s.global.enabled)
        XCTAssertNil(s.global.selectedModel)
        XCTAssertTrue(s.global.collectInputs)
    }
}
