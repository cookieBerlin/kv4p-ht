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
                    TextField("Your callsign", text: $callsign, prompt: Text("N0CALL"))
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
                Button("Continue") { model.completeStationSetup(callsign: callsign) }
                    .disabled(!isEntered)
                Button("Listen only") { model.chooseListenOnly() }
            } footer: {
                Text(ControlHelp.listenOnly)
            }
        }
        .formStyle(.grouped)
        .interactiveDismissDisabled()
        #if os(macOS)
            .frame(minWidth: 420, minHeight: 300)
        #endif
    }
}
