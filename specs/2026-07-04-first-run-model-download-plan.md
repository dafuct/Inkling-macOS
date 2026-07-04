# First-Run Model Download Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On first launch with no AI model installed, open Settings to a Model pane whose Download button fetches `gemma-4-e4b-it-4bit` from Hugging Face in-process, then hot-loads the engine so suggestions work with no restart.

**Architecture:** Pure, testable logic (path resolution, download state machine + atomic install) lives in `InklingCore` with XCTest coverage. The Hugging Face call (`HubApi.snapshot`) and the SwiftUI pane live in the `Inkling` app target behind a `ModelSnapshotDownloading` protocol. Completion posts the existing `.inklingModelChanged` notification, which `AppDelegate` already observes to rebuild a fresh `MLXEngine` — so hot-load needs no new engine plumbing.

**Tech Stack:** Swift 6 (tools 6.0, language mode 5 for the app target), SwiftUI + AppKit, `swift-transformers` `Hub` product (`HubApi`), XCTest.

## Global Constraints

- Model repo id: `mlx-community/gemma-4-e4b-it-4bit` (~4.9 GB). Installed folder name: `gemma-4-e4b-it-4bit` (equals `ModelConfig.defaultModelName`).
- Install destination: `~/Library/Application Support/Inkling/models/<name>` (created on demand).
- No app restart after download — reuse `Notification.Name.inklingModelChanged`, already observed at `AppDelegate.swift:55-59` → `reloadEngine()`.
- Pure/testable code goes in `InklingCore` (the only target with a test target: `Tests/InklingCoreTests`). HubApi + SwiftUI stay in the `Inkling` app target.
- Tests use XCTest with `@testable import InklingCore`. Run core tests with `swift test` (the test target depends only on `InklingCore`, so no MLX/Metal build).
- A model folder is identified by containing `config.json` (`ModelCatalog.availableModels`).
- Download button copy: `Download gemma-4-e4b-it-4bit (~4.9 GB)`.
- Commit messages: NO AI attribution / Co-Authored-By (project rule).
- Platform: macOS 14+.

---

## File Structure

**Create:**
- `Sources/InklingCore/ModelInstallLocator.swift` — pure resolution of install root + read/search root.
- `Sources/InklingCore/ModelDownloadController.swift` — `ModelDownloadState`, `ModelSnapshotDownloading` protocol, and the `@MainActor` `ObservableObject` state machine that downloads to staging then atomically moves into place.
- `Sources/Inkling/HubModelDownloader.swift` — `ModelSnapshotDownloading` impl over `HubApi`.
- `Sources/Inkling/ModelPane.swift` — SwiftUI pane with the download UI.
- `Tests/InklingCoreTests/ModelInstallLocatorTests.swift`
- `Tests/InklingCoreTests/ModelDownloadControllerTests.swift`

**Modify:**
- `Package.swift` — add the `Hub` product to the `Inkling` target's dependencies.
- `Sources/Inkling/ModelConfig.swift:11-22` — resolve `modelsRoot` and a new `installRoot` via `ModelInstallLocator`.
- `Sources/Inkling/SettingsRootView.swift:5-27,29-58` — add `.model` section, route it to `ModelPane`, accept an initial selection.
- `Sources/Inkling/SettingsWindowController.swift:9-23` — `show(select:)` overload.
- `Sources/Inkling/AppDelegate.swift:52-129` — first-run auto-open of the Model pane.

---

## Task 1: `ModelInstallLocator` — pure root resolution (InklingCore)

**Files:**
- Create: `Sources/InklingCore/ModelInstallLocator.swift`
- Test: `Tests/InklingCoreTests/ModelInstallLocatorTests.swift`

**Interfaces:**
- Produces:
  - `ModelInstallLocator.installRoot(appSupport: URL) -> URL`
  - `ModelInstallLocator.readRoot(bundledModels: URL?, installRoot: URL, devModels: URL?, fileManager: FileManager = .default) -> URL`

- [ ] **Step 1: Write the failing test**

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ModelInstallLocatorTests`
Expected: FAIL — `cannot find 'ModelInstallLocator' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ModelInstallLocatorTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/InklingCore/ModelInstallLocator.swift Tests/InklingCoreTests/ModelInstallLocatorTests.swift
git commit -m "feat(core): ModelInstallLocator — pure install/read root resolution"
```

---

## Task 2: `ModelDownloadController` — state machine + atomic install (InklingCore)

**Files:**
- Create: `Sources/InklingCore/ModelDownloadController.swift`
- Test: `Tests/InklingCoreTests/ModelDownloadControllerTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `enum ModelDownloadState: Equatable, Sendable { case idle; case downloading(fraction: Double, speedBytesPerSec: Double?); case installing; case done; case failed(message: String) }`
  - `protocol ModelSnapshotDownloading: Sendable { func download(repoId: String, into stagingBase: URL, onProgress: @escaping @Sendable (Double, Double?) -> Void) async throws -> URL }`
  - `@MainActor final class ModelDownloadController: ObservableObject` with:
    - `init(downloader: ModelSnapshotDownloading, repoId: String, modelName: String, installRoot: URL, fileManager: FileManager = .default, onInstalled: @escaping (String) -> Void)`
    - `@Published private(set) var state: ModelDownloadState`
    - `func start()` (fire-and-forget; UI)
    - `func performDownload() async` (the awaited body; used by tests)
    - `func cancel()`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/InklingCoreTests/ModelDownloadControllerTests.swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ModelDownloadControllerTests`
Expected: FAIL — `cannot find 'ModelDownloadController' / 'ModelSnapshotDownloading' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/InklingCore/ModelDownloadController.swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ModelDownloadControllerTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/InklingCore/ModelDownloadController.swift Tests/InklingCoreTests/ModelDownloadControllerTests.swift
git commit -m "feat(core): ModelDownloadController — staged download + atomic install state machine"
```

---

## Task 3: `HubModelDownloader` — HubApi implementation (app target)

**Files:**
- Modify: `Package.swift` (add `Hub` product to the `Inkling` target)
- Create: `Sources/Inkling/HubModelDownloader.swift`

**Interfaces:**
- Consumes: `ModelSnapshotDownloading` (Task 2).
- Produces: `struct HubModelDownloader: ModelSnapshotDownloading` (default init).

No unit test — the real HF/network call is the thing behind the protocol. Verified by a package build.

- [ ] **Step 1: Add the `Hub` product to the `Inkling` target**

In `Package.swift`, the `Inkling` executable target's `dependencies` array (currently `InklingCore`, `InklingMLX`, the MLX products, and `Tokenizers`), add:

```swift
                .product(name: "Hub", package: "swift-transformers"),
```

- [ ] **Step 2: Write the implementation**

```swift
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
```

- [ ] **Step 3: Build to verify it compiles**

Run: `./Scripts/bundle.sh`
Expected: `** BUILD SUCCEEDED **` then `Built and signed Inkling.app`.
(If `import Hub` fails, confirm the `Package.swift` edit from Step 1 was saved and rerun.)

- [ ] **Step 4: Commit**

```bash
git add Package.swift Sources/Inkling/HubModelDownloader.swift
git commit -m "feat(app): HubModelDownloader — in-process HF snapshot download via HubApi"
```

---

## Task 4: Wire `ModelConfig` to the locator (app target)

**Files:**
- Modify: `Sources/Inkling/ModelConfig.swift:11-22`

**Interfaces:**
- Consumes: `ModelInstallLocator` (Task 1).
- Produces: `ModelConfig.installRoot: URL` (new); `ModelConfig.modelsRoot: URL` (now locator-backed).

No new unit test (resolution logic is covered by Task 1). Verified by build + existing tests.

- [ ] **Step 1: Replace the `modelsRoot` definition and add `installRoot`**

Replace lines 11-22 (the `static let modelsRoot: URL = { ... }()` block) with:

```swift
    /// The single writable install destination for downloaded models:
    /// ~/Library/Application Support/Inkling/models (created on demand).
    static let installRoot: URL = {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(filePath: NSHomeDirectory()).appending(path: "Library/Application Support")
        return ModelInstallLocator.installRoot(appSupport: appSupport)
    }()

    /// Root folder searched for installed models. Prefers models bundled inside
    /// the app, then the install root once populated, then a dev checkout.
    static let modelsRoot: URL = {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("models", isDirectory: true)
        let dev = URL(filePath: "/Users/makar/dev/own-cotypist/models")
        return ModelInstallLocator.readRoot(
            bundledModels: bundled, installRoot: installRoot, devModels: dev)
    }()
```

- [ ] **Step 2: Verify core tests still pass and the app builds**

Run: `swift test`
Expected: PASS (all existing InklingCore tests + Tasks 1-2).

Run: `./Scripts/bundle.sh`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Sources/Inkling/ModelConfig.swift
git commit -m "refactor(app): ModelConfig install/read roots via ModelInstallLocator"
```

---

## Task 5: `ModelPane` + Settings routing (app target)

**Files:**
- Create: `Sources/Inkling/ModelPane.swift`
- Modify: `Sources/Inkling/SettingsRootView.swift:5-27` (add `.model` case) and `:29-58` (route it + accept initial selection)

**Interfaces:**
- Consumes: `ModelDownloadController`, `ModelDownloadState` (Task 2); `HubModelDownloader` (Task 3); `ModelConfig.installRoot`, `ModelConfig.modelsRoot`, `ModelConfig.defaultModelName` (Task 4); `ModelCatalog.availableModels`; `SettingsStore.shared`; `Notification.Name.inklingModelChanged`.
- Produces: `struct ModelPane: View`; `SettingsSection.model`; `SettingsRootView(initialSection:)`.

No unit test (SwiftUI/AppKit). Verified by build + manual smoke in Task 6.

- [ ] **Step 1: Add the `.model` section**

In `SettingsRootView.swift`, add a case to `SettingsSection` (place it right after `general`) and an icon:

```swift
    case general = "General"
    case model = "Model"
```

and in `var icon`:

```swift
        case .general: "gearshape"
        case .model: "arrow.down.circle"
```

- [ ] **Step 2: Route `.model` and accept an initial selection**

Change `SettingsRootView` to take an initial section and route the new case:

```swift
struct SettingsRootView: View {
    @State private var selection: SettingsSection?

    init(initialSection: SettingsSection = .general) {
        _selection = State(initialValue: initialSection)
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            switch selection ?? .general {
            case .general:
                GeneralPane()
            case .model:
                ModelPane()
            case .appSettings:
                AppSettingsPane()
            case .personalization:
                PersonalizationPane()
            case .context:
                ContextPane()
            case .labs:
                LabsPane()
            case .statistics:
                StatisticsPane()
            case .about:
                AboutPane()
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}
```

- [ ] **Step 3: Write `ModelPane`**

```swift
// Sources/Inkling/ModelPane.swift
import InklingCore
import SwiftUI

/// First-run / no-model pane: downloads the default model and hot-loads it.
/// Also the re-download surface if the user later deletes their only model.
struct ModelPane: View {
    @StateObject private var controller = ModelPane.makeController()

    private static func makeController() -> ModelDownloadController {
        ModelDownloadController(
            downloader: HubModelDownloader(),
            repoId: "mlx-community/\(ModelConfig.defaultModelName)",
            modelName: ModelConfig.defaultModelName,
            installRoot: ModelConfig.installRoot
        ) { name in
            // Select the freshly-installed model and let AppDelegate hot-load it.
            SettingsStore.shared.state.global.selectedModel = name
            NotificationCenter.default.post(name: .inklingModelChanged, object: nil)
        }
    }

    private var installedModels: [String] {
        ModelCatalog.availableModels(in: ModelConfig.modelsRoot)
    }

    var body: some View {
        Form {
            if installedModels.isEmpty {
                switch controller.state {
                case .idle:
                    Section {
                        Text("Inkling needs an on-device AI model to suggest completions.")
                        Text("The model runs entirely on your Mac — nothing is sent to a server.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Download \(ModelConfig.defaultModelName) (~4.9 GB)") {
                            controller.start()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                case let .downloading(fraction, speed):
                    Section("Downloading") {
                        ProgressView(value: fraction)
                        Text(Self.progressCaption(fraction: fraction, speed: speed))
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Cancel") { controller.cancel() }
                    }
                case .installing:
                    Section { ProgressView().controlSize(.small); Text("Installing…") }
                case .done:
                    Section { Label("Model ready.", systemImage: "checkmark.circle.fill") }
                case let .failed(message):
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Button("Retry") { controller.start() }
                    }
                }
            } else {
                Section("Installed model") {
                    Text(ModelConfig.currentModelName)
                    Text("Switch or add models in General.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Model")
    }

    private static func progressCaption(fraction: Double, speed: Double?) -> String {
        let pct = Int((fraction * 100).rounded())
        guard let speed, speed > 0 else { return "\(pct)%" }
        let mbps = speed / 1_000_000
        return String(format: "%d%% · %.1f MB/s", pct, mbps)
    }
}
```

- [ ] **Step 4: Build to verify it compiles**

Run: `./Scripts/bundle.sh`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Inkling/ModelPane.swift Sources/Inkling/SettingsRootView.swift
git commit -m "feat(app): Model settings pane with in-app download + hot-load"
```

---

## Task 6: First-run auto-open + end-to-end verification (app target)

**Files:**
- Modify: `Sources/Inkling/SettingsWindowController.swift:9-23`
- Modify: `Sources/Inkling/AppDelegate.swift:52-129`

**Interfaces:**
- Consumes: `SettingsRootView(initialSection:)` (Task 5); `ModelCatalog.availableModels`; `ModelConfig.modelsRoot`.
- Produces: `SettingsWindowController.show(select: SettingsSection?)`.

- [ ] **Step 1: Add a section-routing `show` on the window controller**

Replace the body of `SettingsWindowController` with:

```swift
final class SettingsWindowController {
    private var window: NSWindow?

    func show(select section: SettingsSection? = nil) {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            w.title = "Inkling Settings"
            w.contentView = NSHostingView(rootView: SettingsRootView(initialSection: section ?? .general))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
```

(The existing `openSettings()` call site `settingsWindow.show()` in `AppDelegate.swift:193` still compiles — `section` defaults to nil.)

- [ ] **Step 2: Auto-open the Model pane on first run**

At the end of `applicationDidFinishLaunching` in `AppDelegate.swift` (immediately after the `Task { await engine.preload() }` / `NSLog(... pre-warming ...)` lines at 127-128), add:

```swift
        if ModelCatalog.availableModels(in: ModelConfig.modelsRoot).isEmpty {
            NSLog("Inkling: no model installed — opening Model pane for first-run download")
            settingsWindow.show(select: .model)
        }
```

- [ ] **Step 3: Build**

Run: `./Scripts/bundle.sh`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual first-run smoke test (no model present)**

```bash
# Move any existing installed models aside so first-run triggers.
mv ~/Library/Application\ Support/Inkling/models ~/Library/Application\ Support/Inkling/models.bak 2>/dev/null || true
open Inkling.app
```

Expected: the Settings window opens focused on the **Model** pane showing the
"Inkling needs an on-device AI model…" copy and the
`Download gemma-4-e4b-it-4bit (~4.9 GB)` button.

- [ ] **Step 5: Manual download + hot-load test (optional, ~4.9 GB / network)**

Click **Download**. Expected: progress bar advances with a `% · MB/s` caption;
on completion the pane shows "Model ready.", the menu-bar **Model** list now lists
`gemma-4-e4b-it-4bit` with a checkmark, and typing in any text field produces
suggestions **without restarting the app**. Confirm the model is at
`~/Library/Application Support/Inkling/models/gemma-4-e4b-it-4bit/config.json`.

Restore any backed-up models afterward:

```bash
rm -rf ~/Library/Application\ Support/Inkling/models 2>/dev/null || true
mv ~/Library/Application\ Support/Inkling/models.bak ~/Library/Application\ Support/Inkling/models 2>/dev/null || true
```

- [ ] **Step 6: Commit**

```bash
git add Sources/Inkling/SettingsWindowController.swift Sources/Inkling/AppDelegate.swift
git commit -m "feat(app): open Model pane on first run when no model is installed"
```

---

## Notes for the implementer

- **Why the notification, not a direct call:** `AppDelegate` already observes
  `.inklingModelChanged` (`AppDelegate.swift:55-59`) and calls `reloadEngine()`,
  which builds a fresh `MLXEngine(modelDirectory:)` and pre-warms it. Posting the
  notification from the pane reuses that path verbatim — no new engine plumbing,
  no restart.
- **`modelsRoot` is resolved once at launch (a `let`).** On a fresh install it
  resolves to `installRoot` (nothing else exists), and the download installs into
  that same `installRoot`, so `ModelCatalog.availableModels` (which re-scans the
  directory on each call) sees the new model without the cached path going stale.
- **Staging lives at `installRoot/.staging`** so the move into
  `installRoot/<name>` is same-volume and atomic. `ModelCatalog` ignores it (no
  `config.json` directly inside, and it is a dotfile sibling, not a model dir).
