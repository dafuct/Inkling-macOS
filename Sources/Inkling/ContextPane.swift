import InklingCore
import SwiftUI

/// Cotypist's "Context" screen. G1 ships the clipboard toggle; screenshot/OCR
/// context (G2) will add a section here later.
struct ContextPane: View {
    @Bindable var store = SettingsStore.shared

    var body: some View {
        Form {
            Section("Clipboard") {
                Toggle("Use clipboard as context (experimental)",
                       isOn: $store.state.global.useClipboardContext)
                Text("When you've copied text in the last minute, Inkling gives it to the on-device model as a hint so completions can reference it. Text-only and processed locally; password-manager and secure-field clipboards are ignored. Per-app overrides live in App Settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Context")
    }
}
