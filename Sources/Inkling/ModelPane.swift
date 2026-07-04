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
