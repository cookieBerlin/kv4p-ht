import KV4PAPRS
import KV4PRadio
import SwiftUI

/// The APRS packets heard on air, newest first, and a line to send messages; the settings are in `SettingsView`.
struct APRSView: View {
    @Bindable var model: RadioViewModel
    @State private var text = ""
    @State private var isOnScreen = false
    @FocusState private var isWriting: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isPageOnScreen) private var isPageOnScreen

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
            Picker("Show", selection: $model.aprsPage) {
                Text("Packets").tag(APRSPage.packets)
                Text(model.newAPRSMessages > 0 ? "Chats (\(model.newAPRSMessages))" : "Chats").tag(APRSPage.chats)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            .padding(.top, 6)
            switch model.aprsPage {
            case .packets: APRSPacketList(model: model, list: .main)
            case .chats: APRSChatsView(model: model)
            }
            // A chat has its own line to write.
            if model.aprsPage == .packets {
                Divider()
                if model.canSendOnAir {
                    composer.padding(8)
                } else if let blocked = model.transmitBlockedText {
                    Text(blocked).font(.footnote).foregroundStyle(.secondary).padding(8)
                }
            }
        }
        .onAppear {
            isOnScreen = true
            updateVisibility()
        }
        .onDisappear {
            isOnScreen = false
            updateVisibility()
        }
        .onChange(of: scenePhase) { updateVisibility() }
        .onChange(of: isPageOnScreen) { updateVisibility() }
    }

    private func updateVisibility() {
        model.isAPRSVisible = isOnScreen && isPageOnScreen && scenePhase == .active
    }

    private var composer: some View {
        HStack {
            recipientField.frame(width: 140).help(ControlHelp.recipient)
            HelpButton(ControlHelp.recipient)
            messageField
            sendButton.labelStyle(.iconOnly)
        }
        .textFieldStyle(.roundedBorder)
        .onChange(of: model.aprsReplyCount) { isWriting = true }
    }

    private var recipientField: some View {
        // iOS: a phone has room for the short label only.
        #if os(macOS)
            TextField("To (empty: bulletin)", text: $model.aprsRecipient)
        #else
            TextField("To", text: $model.aprsRecipient)
        #endif
    }

    private var messageField: some View {
        TextField("Message", text: $text)
            .focused($isWriting)
            .onSubmit(send)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isWriting = false }
                }
            }
    }

    private var sendButton: some View {
        Button("Send", systemImage: "paperplane", action: send)
            .disabled(!model.isReady || text.isEmpty)
    }

    private func send() {
        guard !text.isEmpty else { return }
        model.sendAPRSMessage(to: model.aprsRecipient, text: text)
        text = ""
    }
}
