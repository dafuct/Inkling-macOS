// Sources/Inkling/HubModelDownloader.swift
import Foundation
import Hub
import InklingCore

/// Downloads a model snapshot from the Hugging Face Hub in-process using
/// swift-transformers' HubApi. Files land under `stagingBase/models/<repoId>`;
/// the returned URL is that folder, which the controller moves into place.
struct HubModelDownloader: ModelSnapshotDownloading {
    func download(
        repoId: String, into stagingBase: URL,
        onProgress: @escaping @Sendable (Double, Double?) -> Void
    ) async throws -> URL {
        let api = HubApi(downloadBase: stagingBase)
        // Empty `matching` downloads all repo files.
        return try await api.snapshot(from: repoId) { (progress: Progress, speed: Double?) in
            onProgress(progress.fractionCompleted, speed)
        }
    }
}
