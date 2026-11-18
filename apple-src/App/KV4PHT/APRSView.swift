import KV4PAPRS
import KV4PRadio
import SwiftUI

/// The APRS packets heard on air, newest first, and a line to send messages; the settings are in `SettingsView`.
struct APRSView: View {
    @Bindable var model: RadioViewModel
    /// On a phone, the packets and the chats are pages of their own, which say whether they are on screen; elsewhere
    /// the view shows the one chosen beside the memories.
    var page: APRSPage?
    @State private var isOnScreen = false
    @FocusState private var isWriting: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isPageOnScreen) private var isPageOnScreen
    @Environment(\.dynamicTypeSize) private var textSize

    private var isAccessibilitySize: Bool { textSize.isAccessibilitySize }

    var body: some View {
        VStack(spacing: 0) {
            if model.isBeaconEnabled, model.canSendOnAir {
                Label(
                    "Position beacon on · accuracy: \(model.beaconAccuracy.label)",
                    systemImage: "location.fill"
                )
                .font(.footnote)
                .foregroundStyle(Color.strongSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            switch shownPage {
            case .packets: APRSPacketList(model: model, list: .main)
            case .chats: APRSChatsView(model: model)
            }
            // A chat has its own line to write.
            if shownPage == .packets {
                Divider()
                // Without a way to send, the reason in place of the line to write, rather than a line that does nothing.
                if let blocked = model.aprsSendBlockedText {
                    Text(blocked).font(.footnote).foregroundStyle(Color.strongSecondary).padding(8)
                } else {
                    composer.padding(8)
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

    private var shownPage: APRSPage { page ?? model.aprsPage }

    /// A phone's pages tell it themselves, as both of them are there at once.
    private func updateVisibility() {
        guard page == nil else { return }
        model.isAPRSVisible = isOnScreen && isPageOnScreen && scenePhase == .active
    }

    /// The recipient and the message side by side, or one below the other with the accessibility text sizes.
    private var composer: some View {
        AdaptiveStack {
            recipientField.frame(maxWidth: isAccessibilitySize ? .infinity : 140)
            HStack {
                messageField
                KeyboardDismissButton()
                SendButton(isDisabled: model.aprsDraft.isEmpty, action: send)
            }
        }
        .textFieldStyle(.roundedBorder)
        .onChange(of: model.aprsReplyCount) { isWriting = true }
    }

    /// Empty, it says whom the message goes to; the whole of it is a hint for VoiceOver and a tooltip on the Mac.
    private var recipientField: some View {
        TextField("To: all", text: $model.aprsRecipient)
            .macName("To")
            .help(ControlHelp.recipient)
            .accessibilityHint(ControlHelp.recipient)
    }

    private var messageField: some View {
        TextField("Message", text: $model.aprsDraft)
            .macName("Message")
            .focused($isWriting)
            .onSubmit(send)
    }

    private func send() {
        model.sendAPRSDraft()
    }
}

/// Sends what was written, below the packets and in a chat: a filled circle, to see as the button of the line, and grey
/// while there is nothing to send.
struct SendButton: View {
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button("Send", systemImage: "paperplane.fill", action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            // Large enough for a finger, as tall as the line or a little more.
            .controlSize(.large)
            .disabled(isDisabled)
    }
}
