import SwiftUI

/// Cotypist Labs: experimental features. Currently the global mid-line
/// completions toggle; alternative suggestions (subproject H) will join here.
struct LabsPane: View {
    @Bindable var store = SettingsStore.shared

    var body: some View {
        Form {
            Section("Labs") {
                Toggle("Enable mid-line completions", isOn: $store.state.global.midLineEnabled)
                Text("Show completions even when text follows the cursor on the same line. Completions continue your sentence forward from the cursor rather than filling gaps. Experimental — expect rough edges; turn it off per-app in App Settings if it gets in the way.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("“Show alternative suggestions” arrives with a later update.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Labs")
    }
}
