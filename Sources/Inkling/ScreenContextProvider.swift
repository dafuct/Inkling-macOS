import AppKit
import CoreGraphics
import ScreenCaptureKit
import Vision

/// Captures the focused window and OCRs it, off the completion path, caching the
/// result. `recentText` is a pure read of the cache; `refreshIfNeeded` kicks a
/// background capture when stale/authorized. Main-actor use only for the cache
/// and the two entry points; the capture+OCR runs on a background task and hops
/// back to the main actor to store its result. Requires Screen Recording
/// authorization; a no-op until granted.
final class ScreenContextProvider {
    private struct Cache { let text: String; let capturedAt: Date; let windowKey: String }
    private var cache: Cache?
    private var isCapturing = false
    private let refreshTTL: TimeInterval = 10

    // MARK: Authorization

    static func isAuthorized() -> Bool { CGPreflightScreenCaptureAccess() }

    /// Triggers the system Screen Recording prompt / adds the app to the list.
    /// If already denied, also open the Settings pane so the user can flip it.
    func requestAuthorization() {
        if !CGRequestScreenCaptureAccess() {
            if let url = URL(string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: Read

    /// The cached OCR text if captured within `window` seconds; nil otherwise.
    func recentText(window: TimeInterval, now: Date) -> String? {
        guard let cache, now.timeIntervalSince(cache.capturedAt) <= window else { return nil }
        return cache.text.isEmpty ? nil : cache.text
    }

    // MARK: Refresh

    /// Kick a background capture if authorized, not already capturing, not in a
    /// secure field, and the cache is stale (older than the TTL, a different
    /// window, or absent). Returns immediately.
    func refreshIfNeeded(now: Date) {
        guard Self.isAuthorized(), !isCapturing,
              !FocusContextProvider.isSecureFieldFocused(),
              let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        let key = "\(pid)"
        if let cache, cache.windowKey == key, now.timeIntervalSince(cache.capturedAt) < refreshTTL {
            return   // fresh enough for this window
        }
        isCapturing = true
        Task { [weak self] in
            let text = await Self.captureAndOCR(pid: pid)
            await MainActor.run {
                guard let self else { return }
                if let text { self.cache = Cache(text: text, capturedAt: now, windowKey: key) }
                self.isCapturing = false
            }
        }
    }

    // MARK: Capture + OCR (background)

    /// Capture the frontmost app's focused on-screen window and OCR it. nil on any
    /// failure. Never logs the image or the text.
    private static func captureAndOCR(pid: pid_t) async -> String? {
        guard let image = await captureFocusedWindow(pid: pid) else { return nil }
        return await recognizeText(in: image)
    }

    private static func captureFocusedWindow(pid: pid_t) async -> CGImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            // The frontmost app's largest on-screen layer-0 window ~ its main window.
            let windows = content.windows.filter {
                $0.owningApplication?.processID == pid && $0.windowLayer == 0 && $0.isOnScreen
            }
            guard let window = windows.max(by: {
                ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height)
            }) else { return nil }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width)
            config.height = Int(window.frame.height)
            config.showsCursor = false
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)
        } catch {
            return nil
        }
    }

    private static func recognizeText(in image: CGImage) async -> String? {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                let joined = lines.joined(separator: "\n")
                continuation.resume(returning: joined.isEmpty ? nil : joined)
            }
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do { try handler.perform([request]) }
            catch { continuation.resume(returning: nil) }
        }
    }
}
