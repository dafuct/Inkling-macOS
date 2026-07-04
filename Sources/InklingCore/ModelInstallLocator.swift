// Sources/InklingCore/ModelInstallLocator.swift
import Foundation

/// Resolves where models are installed to (a single writable root) and where the
/// app searches for them. Pure so it can be unit-tested without touching the real
/// bundle or Application Support.
public enum ModelInstallLocator {
    /// The single writable install destination: <appSupport>/Inkling/models.
    /// The caller creates it on demand (e.g. the downloader).
    public static func installRoot(appSupport: URL) -> URL {
        appSupport
            .appending(path: "Inkling", directoryHint: .isDirectory)
            .appending(path: "models", directoryHint: .isDirectory)
    }

    /// The read/search root. Precedence: models bundled in the app, then the
    /// install root once it exists, then a dev-checkout path when present, else
    /// the install root (empty on a fresh install — triggers onboarding).
    public static func readRoot(
        bundledModels: URL?, installRoot: URL, devModels: URL?,
        fileManager: FileManager = .default
    ) -> URL {
        if let bundledModels, fileManager.fileExists(atPath: bundledModels.path) {
            return bundledModels
        }
        if fileManager.fileExists(atPath: installRoot.path) { return installRoot }
        if let devModels, fileManager.fileExists(atPath: devModels.path) { return devModels }
        return installRoot
    }
}
