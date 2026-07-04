import XCTest
@testable import InklingCore

/// Stub that writes a fake model folder (with config.json) into the staging base
/// under the HubApi layout `models/<org>/<repo>` and returns it, after emitting
/// a progress tick. `failWith` makes it throw instead.
private struct StubDownloader: ModelSnapshotDownloading {
    var failWith: Error?
    func download(repoId: String, into stagingBase: URL,
                  onProgress: @escaping @Sendable (Double, Double?) -> Void) async throws -> URL {
        onProgress(0.5, 1_000_000)
        if let failWith { throw failWith }
        let folder = stagingBase
            .appending(path: "models", directoryHint: .isDirectory)
            .appending(path: repoId, directoryHint: .isDirectory) // e.g. mlx-community/gemma-...
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "{}".data(using: .utf8)!.write(to: folder.appending(path: "config.json"))
        onProgress(1.0, 1_000_000)
        return folder
    }
}

private struct DummyError: Error {}

@MainActor
final class ModelDownloadControllerTests: XCTestCase {
    private var installRoot: URL!
    override func setUpWithError() throws {
        installRoot = URL(filePath: NSTemporaryDirectory())
            .appending(path: "install-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: installRoot) }

    private func make(_ downloader: ModelSnapshotDownloading, installed: @escaping (String) -> Void = { _ in })
        -> ModelDownloadController {
        ModelDownloadController(
            downloader: downloader, repoId: "mlx-community/gemma-4-e4b-it-4bit",
            modelName: "gemma-4-e4b-it-4bit", installRoot: installRoot, onInstalled: installed)
    }

    func test_success_installs_model_and_reports_done() async throws {
        var installedName: String?
        let c = make(StubDownloader()) { installedName = $0 }
        await c.performDownload()
        XCTAssertEqual(c.state, .done)
        XCTAssertEqual(installedName, "gemma-4-e4b-it-4bit")
        let config = installRoot
            .appending(path: "gemma-4-e4b-it-4bit", directoryHint: .isDirectory)
            .appending(path: "config.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: config.path))
        // staging cleaned
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: installRoot.appending(path: ".staging").path))
    }

    func test_failure_sets_failed_and_does_not_call_installed() async throws {
        var called = false
        let c = make(StubDownloader(failWith: DummyError())) { _ in called = true }
        await c.performDownload()
        if case .failed = c.state {} else { XCTFail("expected .failed, got \(c.state)") }
        XCTAssertFalse(called)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: installRoot.appending(path: ".staging").path))
    }

    func test_retry_after_failure_succeeds() async throws {
        let c = make(StubDownloader(failWith: DummyError()))
        await c.performDownload()
        if case .failed = c.state {} else { XCTFail("expected .failed") }
        // swap to a succeeding downloader and retry
        let c2 = make(StubDownloader())
        await c2.performDownload()
        XCTAssertEqual(c2.state, .done)
    }

    func test_reinstall_replaces_existing_model_folder() async throws {
        // Pre-existing stale folder at the destination.
        let dest = installRoot.appending(path: "gemma-4-e4b-it-4bit", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try "stale".data(using: .utf8)!.write(to: dest.appending(path: "old.txt"))
        let c = make(StubDownloader())
        await c.performDownload()
        XCTAssertEqual(c.state, .done)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appending(path: "old.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appending(path: "config.json").path))
    }
}
