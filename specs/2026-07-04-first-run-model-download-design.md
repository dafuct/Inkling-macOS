# First-Run Model Download — Design

**Date:** 2026-07-04
**Status:** Approved (design), pending implementation plan

## Problem

Inkling ships as a slim DMG with **no AI model bundled** (models exceed GitHub's
2 GB release-asset limit). On a fresh install the model tier silently produces
nothing: `MLXEngine.loadedContainer()` throws on the missing model, the error is
caught and logged, and `suggestion()` returns `""` (`MLXEngine.swift:70-73`).
There is no onboarding, so a new user has a running menu-bar app that never
suggests anything and no in-app way to fix it.

## Goal

First launch with no model installed →

1. The Settings window opens automatically, routed to a new **Model** pane.
2. The user clicks **Download** and the model is fetched **in-process** from
   Hugging Face with a live progress bar.
3. On completion the engine **hot-loads** the new model — the user can start
   using suggestions immediately, **with no app restart**.

Target model: `mlx-community/gemma-4-e4b-it-4bit` (~4.9 GB) — the code default
(`ModelConfig.defaultModelName`). Single model; no in-pane chooser (the General
pane already lets a user switch among installed models).

## Approach

### Download mechanism: in-process `HubApi.snapshot`

The app already links `swift-transformers` (via the `Tokenizers` product), which
ships `Hub`/`HubApi`:

```
// swift-transformers/Sources/Hub/HubApi.swift
public func snapshot(from repoId: String, revision: String = "main",
                     matching globs: [String] = [],
                     progressHandler: @escaping (Progress, Double?) -> Void) async throws -> URL
```

- Async download with a `Progress` (fraction complete) + optional speed
  (bytes/sec) callback.
- `HubApi(downloadBase:)` is configurable; `snapshot` returns the materialized
  local folder URL (layout `downloadBase/models/<org>/<repo>`).
- Resumable via HubApi's own cache; no Python, no `hf` CLI.

Rejected alternatives: shelling out to `Scripts/fetch-models.sh` (requires the
user to have Python + `huggingface_hub` — a non-starter for a drag-to-Applications
app); bundling the model in the DMG (>2 GB, deliberately avoided).

## Components

### 1. `ModelConfig` resolver fix (`Sources/Inkling/ModelConfig.swift`)

Current `modelsRoot` (lines 11-22) returns Application Support **only if it
already exists**, otherwise a hardcoded dev path
(`/Users/makar/dev/own-cotypist/models`). A fresh install has none of the three,
so it resolves to the dev path, which does not exist on a user's machine.

Changes:

- Add `static var installRoot: URL` = `~/Library/Application Support/Inkling/models`,
  **created on demand**. This is the single writable destination the downloader
  installs into.
- Make `modelsRoot` (the read/search root) resolve to Application Support even
  before it is populated, so `ModelCatalog.availableModels` and the download both
  agree on one location. Precedence:
  1. bundled models inside the app (`Contents/Resources/models`) if present,
  2. otherwise `installRoot` (Application Support),
  3. the dev-checkout path **only when it actually exists** (preserves
     `swift run` dev workflow).

`ModelCatalog.availableModels` already returns `[]` safely for a missing
directory, so pointing at an not-yet-created `installRoot` is harmless.

### 2. `ModelDownloader` (new)

A `@MainActor` `ObservableObject` driving the download state machine, with the
Hugging Face call behind a protocol so the machine is testable without network.

```
protocol ModelSnapshotDownloading {
    // Emits (fraction 0...1, speedBytesPerSec?) and returns the downloaded folder URL.
    func download(repoId: String,
                  into stagingBase: URL,
                  onProgress: @escaping (Double, Double?) -> Void) async throws -> URL
}
```

- Production impl wraps `HubApi(downloadBase: stagingBase).snapshot(...)`.
- States: `idle → downloading(fraction, speed) → installing → done` /
  `failed(message)`.
- Flow: download to a staging dir under `installRoot/.staging`, then **atomically
  move** (`FileManager.moveItem`, same volume → instant) the finished model
  folder to `installRoot/gemma-4-e4b-it-4bit`. Clean up staging on
  success/failure/cancel.
- On success, invokes a completion callback (wired by AppDelegate) with the
  installed model name.

### 3. `ModelPane` (new SwiftUI pane, `Sources/Inkling/`)

Added to the `SettingsRootView` sidebar. Renders from `ModelDownloader` state:

- **No model installed, idle:** welcome copy explaining the app needs a model +
  primary button "Download gemma-4-e4b-it-4bit (~4.9 GB)".
- **Downloading:** determinate progress bar, percent, speed, and a **Cancel**
  button.
- **Installing:** brief indeterminate "Installing…" state during the move.
- **Failed:** error message (distinct copy for offline vs other failures) +
  **Retry**.
- **Model installed:** shows the current installed model name (reuses the
  existing About/General display style). The pane thus also handles the
  re-download case if the user later deletes their only model.

### 4. First-run auto-open (`AppDelegate.applicationDidFinishLaunching`)

After existing setup, if `ModelCatalog.availableModels(in: ModelConfig.modelsRoot)`
is empty, open the Settings window routed to the Model pane. Requires adding
pane-selection routing to `SettingsWindowController` / `SettingsRootView` (a
selected-pane parameter; the sidebar is already a `NavigationSplitView` with a
selection binding).

### 5. Engine hot-load on completion

`ModelDownloader`'s completion callback (owned by AppDelegate):

1. sets `SettingsStore.shared.state.global.selectedModel` to the downloaded name,
2. calls the **existing** `reloadEngine()` path (`AppDelegate.swift:217-231`),
   which builds a fresh `MLXEngine(modelDirectory:)`, calls `preload()`, posts
   `.inklingModelChanged`, and rebuilds the menu.

No restart. The lazy-loading actor design means the fresh engine warms the new
model in the background and suggestions resume once warm.

## Data Flow

```
[Download button]
   → ModelDownloader.start()
   → ModelSnapshotDownloading.download(repoId, into: installRoot/.staging, onProgress)
       → HubApi.snapshot(...)                (progress → pane)
   → FileManager.moveItem(staged → installRoot/gemma-4-e4b-it-4bit)
   → completion(name)
       → SettingsStore.global.selectedModel = name
       → AppDelegate.reloadEngine()
           → MLXEngine(modelDirectory:).preload()
   → suggestions ready
```

## Error Handling

- **Network failure / other errors:** `failed(message)` state, Retry button;
  staging cleaned.
- **Offline:** surfaced with distinct copy (HubApi exposes offline detection via
  `useOfflineMode`); do not present a generic error.
- **Cancel:** stops the task, cleans staging, returns to `idle`.
- **Interrupted mid-move:** move is atomic; a partial staging dir is deleted on
  next start. The install dir only ever contains a fully-moved model.

## Testing

Testable seams (no MLX, no real network in tests):

- **`ModelConfig` root resolution** — unit tests for install/read-root precedence
  (bundled vs Application Support vs dev-checkout) using an injected
  `FileManager` / temp dirs.
- **`ModelDownloader` state machine** — inject a stub `ModelSnapshotDownloading`
  that emits a progress sequence then success or failure into a temp staging
  dir. Assert: state transitions, atomic move into the install root, completion
  callback fires with the right name, staging cleaned, failure/cancel paths.
- **`ModelCatalog`** — existing empty-vs-populated behavior already covered.

The real `HubApi.snapshot` call and the MLX engine reload stay behind their
protocols/existing seams and are exercised manually (build the app, launch with
an empty `installRoot`, download, confirm suggestions appear without restart).

## Out of Scope (YAGNI)

- Multi-model chooser in the Model pane (single model per Q1; General pane
  already switches among installed models).
- Custom cross-launch resume UI (HubApi caches partials; we do not build our own
  resume surface).
- Background download after the app is quit.
- Disk-space precheck (nice-to-have; the failure path already handles a full
  disk).
