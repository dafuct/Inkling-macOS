// Tests/InklingCoreTests/ModelInstallLocatorTests.swift
import XCTest
@testable import InklingCore

final class ModelInstallLocatorTests: XCTestCase {
    private var tmp: URL!
    override func setUpWithError() throws {
        tmp = URL(filePath: NSTemporaryDirectory())
            .appending(path: "locator-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func mkdir(_ name: String) throws -> URL {
        let u = tmp.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func test_installRoot_is_application_support_inkling_models() {
        let appSupport = URL(filePath: "/Users/x/Library/Application Support")
        let root = ModelInstallLocator.installRoot(appSupport: appSupport)
        XCTAssertEqual(root.path, "/Users/x/Library/Application Support/Inkling/models")
    }

    func test_readRoot_prefers_bundled_when_present() throws {
        let bundled = try mkdir("bundled")
        let install = tmp.appending(path: "install", directoryHint: .isDirectory) // not created
        let dev = try mkdir("dev")
        let root = ModelInstallLocator.readRoot(bundledModels: bundled, installRoot: install, devModels: dev)
        XCTAssertEqual(root, bundled)
    }

    func test_readRoot_uses_installRoot_when_it_exists() throws {
        let install = try mkdir("install")
        let dev = try mkdir("dev")
        let root = ModelInstallLocator.readRoot(bundledModels: nil, installRoot: install, devModels: dev)
        XCTAssertEqual(root, install)
    }

    func test_readRoot_falls_back_to_dev_when_install_absent() throws {
        let install = tmp.appending(path: "install", directoryHint: .isDirectory) // not created
        let dev = try mkdir("dev")
        let root = ModelInstallLocator.readRoot(bundledModels: nil, installRoot: install, devModels: dev)
        XCTAssertEqual(root, dev)
    }

    func test_readRoot_defaults_to_installRoot_when_nothing_exists() {
        let install = tmp.appending(path: "install", directoryHint: .isDirectory) // not created
        let root = ModelInstallLocator.readRoot(bundledModels: nil, installRoot: install, devModels: nil)
        XCTAssertEqual(root, install)
    }
}
