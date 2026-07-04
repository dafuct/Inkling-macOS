import AppKit
import InklingCore
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case model = "Model"
    case appSettings = "App Settings"
    case personalization = "Personalization"
    case context = "Context"
    case labs = "Labs"
    case statistics = "Statistics"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .model: "arrow.down.circle"
        case .appSettings: "app.badge.checkmark"
        case .personalization: "brain.head.profile"
        case .context: "photo.on.rectangle"
        case .labs: "flask"
        case .statistics: "chart.bar"
        case .about: "info.circle"
        }
    }
}

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

struct GeneralPane: View {
    @Bindable var store = SettingsStore.shared

    var body: some View {
        Form {
            Section {
                Toggle("Enable completions", isOn: $store.state.global.enabled)
                Text("Master switch. Per-app exceptions live in App Settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Model") {
                Picker("Model", selection: Binding(
                    get: { ModelConfig.currentModelName },
                    set: { name in
                        guard name != ModelConfig.currentModelName else { return }
                        store.state.global.selectedModel = name
                        NotificationCenter.default.post(name: .inklingModelChanged, object: nil)
                    })) {
                    ForEach(ModelCatalog.availableModels(in: ModelConfig.modelsRoot), id: \.self) {
                        Text($0).tag($0)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}

struct PlaceholderPane: View {
    let title: String
    let note: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "hammer")
        } description: {
            Text(note)
        }
        .navigationTitle(title)
    }
}

struct AboutPane: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 64, height: 64)
            Text("Inkling").font(.title2.bold())
            Text("On-device autocomplete for macOS.")
                .foregroundStyle(.secondary)
            Text("Model: \(ModelConfig.currentModelName)")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("About")
    }
}
