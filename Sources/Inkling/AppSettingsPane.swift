import AppKit
import InklingCore
import SwiftUI
import UniformTypeIdentifiers

/// Cotypist-style per-app settings: searchable app list (most used first) on
/// the left, the selected app's overrides form on the right.
struct AppSettingsPane: View {
    @Bindable var store = SettingsStore.shared
    @State private var search = ""
    @State private var selectedBundleID: String?

    private var apps: [(bundleID: String, usage: AppUsageInfo)] {
        let all = store.state.appsSortedByUsage()
        guard !search.isEmpty else { return all }
        return all.filter {
            $0.usage.displayName.localizedCaseInsensitiveContains(search)
                || $0.bundleID.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                TextField("Search", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .padding(8)
                List(selection: $selectedBundleID) {
                    ForEach(apps, id: \.bundleID) { app in
                        HStack {
                            Text(app.usage.displayName)
                            Spacer()
                            Text("\(app.usage.suggestionsShown)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .tag(app.bundleID)
                    }
                }
                Divider()
                HStack {
                    Button {
                        addApp()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .padding(6)
                    Spacer()
                }
            }
            .frame(minWidth: 230, maxWidth: 320)

            if let bundleID = selectedBundleID {
                AppOverridesForm(bundleID: bundleID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Select an app", systemImage: "app",
                    description: Text("Apps appear here once a completion is shown in them, or add one with +."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("App Settings")
        .onChange(of: search) {
            if let sel = selectedBundleID, !apps.contains(where: { $0.bundleID == sel }) {
                selectedBundleID = nil
            }
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier else { return }
        if store.state.appUsage[bundleID] == nil {
            let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                ?? (bundle.infoDictionary?["CFBundleName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent
            store.state.appUsage[bundleID] = AppUsageInfo(displayName: name, lastSeen: Date())
        }
        selectedBundleID = bundleID
    }
}

/// One per-app override with Cotypist's "Default (on/off)" / "On" / "Off" choices.
struct TriStatePicker: View {
    let label: String
    let caption: String
    let globalDefault: Bool
    @Binding var choice: OverrideChoice

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Picker(label, selection: $choice) {
                Text("Default (\(globalDefault ? "on" : "off"))").tag(OverrideChoice.useDefault)
                Text("On").tag(OverrideChoice.on)
                Text("Off").tag(OverrideChoice.off)
            }
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// The overrides form for one app. The perApp entry is created lazily on the
/// first edit, so browsing apps never bloats the settings file.
struct AppOverridesForm: View {
    @Bindable var store = SettingsStore.shared
    let bundleID: String

    var body: some View {
        Form {
            Section("Completions") {
                TriStatePicker(
                    label: "Enable completions",
                    caption: "Turn off for apps with their own autocomplete or where completions aren't needed.",
                    globalDefault: store.state.global.enabled,
                    choice: binding(\.completions))
                TriStatePicker(
                    label: "Enable mid-line completions",
                    caption: "Show completions mid-line for this app (overrides the global Labs setting).",
                    globalDefault: store.state.global.midLineEnabled,
                    choice: binding(\.midLine))
                TriStatePicker(
                    label: "Enable autocorrect",
                    caption: "Stored now; takes effect when autocorrect ships (subproject F).",
                    globalDefault: store.state.global.autocorrectEnabled,
                    choice: binding(\.autocorrect))
                TriStatePicker(
                    label: "Disable accept key (`)",
                    caption: "Let ` type through where it's a real character (Markdown, terminals). Until an alternative shortcut ships, suggestions can't be accepted in such apps.",
                    globalDefault: store.state.global.disableAcceptKeyDefault,
                    choice: binding(\.disableAcceptKey))
            }
            Section("Troubleshooting") {
                Toggle("Improve compatibility with this app", isOn: binding(\.improveCompatibility))
                Text("Reserved for an alternative accessibility strategy (not implemented yet).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Custom Instructions") {
                TextEditor(text: binding(\.customInstructions))
                    .font(.body.monospaced())
                    .frame(minHeight: 120)
                Text("Supplements the global Custom AI Instructions (Personalization) for this app. Takes effect when the experimental instructions toggle is on.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(store.state.appUsage[bundleID]?.displayName ?? bundleID)
    }

    private func binding<T>(_ keyPath: WritableKeyPath<AppOverrides, T>) -> Binding<T> {
        Binding(
            get: { (store.state.perApp[bundleID] ?? AppOverrides())[keyPath: keyPath] },
            set: { newValue in
                var overrides = store.state.perApp[bundleID] ?? AppOverrides()
                overrides[keyPath: keyPath] = newValue
                store.state.perApp[bundleID] = overrides
            })
    }
}
