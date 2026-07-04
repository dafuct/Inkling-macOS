import InklingCore
import SwiftUI

/// The "Context" screen: clipboard (G1) and screen/OCR (G2) context.
struct ContextPane: View {
    @Bindable var store = SettingsStore.shared
    @State private var screenAuthorized = ScreenContextProvider.isAuthorized()

    private let screenProvider = ScreenContextProvider()

    var body: some View {
        Form {
            Section("Clipboard") {
                Toggle("Use clipboard as context (experimental)",
                       isOn: $store.state.global.useClipboardContext)
                Text("When you've copied text in the last minute, Inkling gives it to the on-device model as a hint so completions can reference it. Text-only and processed locally; password-manager and secure-field clipboards are ignored. Per-app overrides live in App Settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Screen") {
                Toggle("Use the focused window as context (experimental)",
                       isOn: $store.state.global.useScreenContext)
                Text("Reads on-screen text from the window you're typing in (via on-device OCR) so completions can reference what's visible. Focused window only — never the whole screen or other apps; secure fields are skipped; images and text are processed locally and never stored. Requires Screen Recording permission. Per-app overrides live in App Settings.")
                    .font(.caption).foregroundStyle(.secondary)

                if store.state.global.useScreenContext && !screenAuthorized {
                    HStack {
                        Text("Screen Recording permission needed")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Grant…") {
                            screenProvider.requestAuthorization()
                            screenAuthorized = ScreenContextProvider.isAuthorized()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Context")
        .onAppear { screenAuthorized = ScreenContextProvider.isAuthorized() }
    }
}
