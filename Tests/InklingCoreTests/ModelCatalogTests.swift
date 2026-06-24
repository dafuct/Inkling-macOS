import XCTest
@testable import InklingCore

final class ModelCatalogTests: XCTestCase {
    private func makeTempRoot() -> URL {
        let root = URL(filePath: NSTemporaryDirectory())
            .appendingPathComponent("inkling-models-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func test_listsOnlyDirsWithConfigJson_sorted() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        for name in ["zeta-model", "alpha-model"] {
            let dir = root.appendingPathComponent(name)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try "{}".write(to: dir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        }
        try fm.createDirectory(at: root.appendingPathComponent("no-config"), withIntermediateDirectories: true)
        try "x".write(to: root.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)

        XCTAssertEqual(ModelCatalog.availableModels(in: root), ["alpha-model", "zeta-model"])
    }

    func test_missingRootReturnsEmpty() {
        let root = URL(filePath: "/no/such/inkling/path")
        XCTAssertEqual(ModelCatalog.availableModels(in: root), [])
    }
}
