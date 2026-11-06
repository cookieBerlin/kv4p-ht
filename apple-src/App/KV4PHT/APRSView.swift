import KV4PAPRS
import KV4PRadio
import SwiftUI

/// The APRS packets heard on air, newest first, and a line to send messages; the settings are in `SettingsView`.
struct APRSView: View {
    @Bindable var model: RadioViewModel
    @State private var recipient = ""
    @State private var text = ""

    var body: some View {
        VStack(spacing: 0) {
            if model.isBeaconEnabled, model.canSendOnAir {
                Label(
                    "Position beacon on · accuracy: \(model.beaconAccuracy.label)",
                    systemImage: "location.fill"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            APRSPacketList(model: model, list: .main)
            Divider()
            if model.canSendOnAir {
                composer.padding(8)
            } else if let blocked = model.transmitBlockedText {
                Text(blocked).font(.footnote).foregroundStyle(.secondary).padding(8)
            }
        }
    }

    private var composer: some View {
        HStack {
            recipientField.frame(width: 140).help(ControlHelp.recipient)
            HelpButton(ControlHelp.recipient)
            messageField
            sendButton.labelStyle(.iconOnly)
        }
        .textFieldStyle(.roundedBorder)
    }

    private var recipientField: some View {
        // iOS: a phone has room for the short label only.
        #if os(macOS)
            TextField("To (empty: bulletin)", text: $recipient)
        #else
            TextField("To", text: $recipient)
        #endif
    }

    private var messageField: some View {
        TextField("Message", text: $text)
            .onSubmit(send)
    }

    private var sendButton: some View {
        Button("Send", systemImage: "paperplane", action: send)
            .disabled(!model.isReady || text.isEmpty)
    }

    private func send() {
        guard !text.isEmpty else { return }
        model.sendAPRSMessage(to: recipient, text: text)
        text = ""
    }
}
