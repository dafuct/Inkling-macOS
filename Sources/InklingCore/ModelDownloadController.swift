import Foundation
import Combine

public enum ModelDownloadState: Equatable, Sendable {
    case idle
    case downloading(fraction: Double, speedBytesPerSec: Double?)
    case installing
    case done
    case failed(message: String)
}

/// Downloads a model snapshot into `stagingBase` and returns the local model
/// folder URL. Behind a protocol so the controller is testable without network.
public protocol ModelSnapshotDownloading: Sendable {
    func download(
        repoId: String, into stagingBase: URL,
        onProgress: @escaping @Sendable (Double, Double?) -> Void
    ) async throws -> URL
}

/// Drives one model download: staging → atomic move into `installRoot/<modelName>`.
/// `@MainActor` so `state` can bind directly to SwiftUI. `onInstalled` fires once
/// the model is on disk (the app uses it to select the model + reload the engine).
@MainActor
public final class ModelDownloadController: ObservableObject {
    @Published public private(set) var state: ModelDownloadState = .idle

    private let downloader: ModelSnapshotDownloading
    private let repoId: String
    private let modelName: String
    private let installRoot: URL
    private let fileManager: FileManager
    private let onInstalled: (String) -> Void
    private var task: Task<Void, Never>?

    public init(
        downloader: ModelSnapshotDownloading, repoId: String, modelName: String,
        installRoot: URL, fileManager: FileManager = .default,
        onInstalled: @escaping (String) -> Void
    ) {
        self.downloader = downloader
        self.repoId = repoId
        self.modelName = modelName
        self.installRoot = installRoot
        self.fileManager = fileManager
        self.onInstalled = onInstalled
    }

    /// Fire-and-forget entry for UI. No-op while a download is in flight.
    public func start() {
        switch state {
        case .downloading, .installing: return
        default: task = Task { await performDownload() }
        }
    }

    public func cancel() {
        task?.cancel()
        try? fileManager.removeItem(at: stagingDir)
        state = .idle
    }

    private var stagingDir: URL {
        installRoot.appending(path: ".staging", directoryHint: .isDirectory)
    }

    /// The awaited download body. Public-for-tests via @testable import.
    func performDownload() async {
        state = .downloading(fraction: 0, speedBytesPerSec: nil)
        let staging = stagingDir
        do {
            try? fileManager.removeItem(at: staging)   // clear any partial
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

            let downloaded = try await downloader.download(repoId: repoId, into: staging) {
                [weak self] fraction, speed in
                Task { @MainActor in
                    self?.state = .downloading(fraction: fraction, speedBytesPerSec: speed)
                }
            }
            try Task.checkCancellation()

            state = .installing
            let dest = installRoot.appending(path: modelName, directoryHint: .isDirectory)
            try fileManager.createDirectory(at: installRoot, withIntermediateDirectories: true)
            try? fileManager.removeItem(at: dest)      // replace stale/partial install
            try fileManager.moveItem(at: downloaded, to: dest)
            try? fileManager.removeItem(at: staging)

            state = .done
            onInstalled(modelName)
        } catch is CancellationError {
            try? fileManager.removeItem(at: staging)
            state = .idle
        } catch {
            try? fileManager.removeItem(at: staging)
            state = .failed(message: Self.message(for: error))
        }
    }

    /// User-facing failure copy; distinguishes offline from other errors.
    static func message(for error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain,
           ns.code == NSURLErrorNotConnectedToInternet || ns.code == NSURLErrorTimedOut
               || ns.code == NSURLErrorNetworkConnectionLost {
            return "No internet connection. Connect and try again."
        }
        return "Download failed: \(error.localizedDescription)"
    }
}
