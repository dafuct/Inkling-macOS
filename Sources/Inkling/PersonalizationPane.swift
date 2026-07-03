import InklingCore
import SwiftUI

/// Cotypist's "Typing History" screen: master collect toggle, the
/// store-without-accepted sub-toggle, the personalize-word-choice slider, and
/// the existing-data count + Delete All.
struct PersonalizationPane: View {
    @Bindable var store = SettingsStore.shared
    @Bindable var inputs = InputStore.shared
    @State private var showDeleteConfirm = false

    private var levelBinding: Binding<Double> {
        Binding(
            get: { Double(store.state.global.personalizeLevel) },
            set: { store.state.global.personalizeLevel = Int($0.rounded()) })
    }

    var body: some View {
        Form {
            Section("Typing History") {
                Toggle("Collect inputs for personalization", isOn: $store.state.global.collectInputs)
                Text("Records the contents of text fields Inkling is active in to improve completions. Stored encrypted, locally on this Mac — never sent anywhere.")
                    .font(.caption).foregroundStyle(.secondary)

                Toggle("Store inputs without accepted completions", isOn: $store.state.global.storeWithoutAccepted)
                    .disabled(!store.state.global.collectInputs)
                    .padding(.leading, 16)
                Text("When on, every input is stored. When off, only inputs where you accepted at least one completion are kept.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Personalize word choice") {
                HStack {
                    Text("Off")
                    Slider(value: levelBinding, in: 0...Double(MemoryEngine.maxPersonalizationLevel), step: 1)
                    Text("Max")
                }
                .disabled(!store.state.global.collectInputs)
                Text("Uses your typing history to favor the words and phrases you prefer. Subtle at low levels; too high may occasionally suggest a less fitting word.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Existing data") {
                HStack {
                    Text("\(inputs.count) inputs collected")
                    Spacer()
                    Button("Delete All…", role: .destructive) { showDeleteConfirm = true }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Personalization")
        .confirmationDialog(
            "Delete all typing history and learned data?",
            isPresented: $showDeleteConfirm, titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                NotificationCenter.default.post(name: .inklingClearLearnedData, object: nil)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes all stored inputs and the personalization model built from them. This can't be undone.")
        }
    }
}
