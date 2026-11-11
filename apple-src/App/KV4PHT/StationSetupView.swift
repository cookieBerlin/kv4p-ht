import KV4PRadio
import SwiftUI

/// Asked at a start without a callsign: transmit with one, or only listen (ADR-0047). It closes only with a choice.
struct StationSetupView: View {
    let model: RadioViewModel
    @State private var callsign = ""

    private var isEntered: Bool { !callsign.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        Form {
            Section {
                LabeledContent("Your callsign") {
                    TextField("Your callsign", text: $callsign, prompt: Text("Enter callsign"))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        #endif
                }
            } header: {
                Text("Welcome to kv4p HT")
            } footer: {
                Text("Transmitting needs an amateur radio licence. Without one, choose Listen only.")
            }
            Section {
                explanation("Continue", ControlHelp.transmitWithCallsign)
                explanation("Listen only", ControlHelp.listenOnly)
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom, spacing: 0) { buttons }
        .interactiveDismissDisabled()
        #if os(macOS)
            .frame(minWidth: 460, minHeight: 360)
        #endif
    }

    private func explanation(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(text).font(.footnote).foregroundStyle(.secondary)
        }
    }

    /// Next to each other, with the main choice on the right, as in the system's own dialogs.
    private var buttons: some View {
        HStack(spacing: 12) {
            Button("Listen only") { model.chooseListenOnly() }
                .buttonStyle(.bordered)
            Button("Continue") { model.completeStationSetup(callsign: callsign) }
                .buttonStyle(.borderedProminent)
                .disabled(!isEntered)
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding()
        .background(Color.opaqueBar)
    }
}
