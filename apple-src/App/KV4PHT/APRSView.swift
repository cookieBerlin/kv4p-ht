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
                .foregroundStyle(.secondary)
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

    private var shownPage: APRSPage { page ?? model.aprsPage }

    /// A phone's pages tell it themselves, as both of them are there at once.
    private func updateVisibility() {
        guard page == nil else { return }
        model.isAPRSVisible = isOnScreen && isPageOnScreen && scenePhase == .active
    }

    /// The recipient and the message side by side, or one below the other with the accessibility text sizes.
    private var composer: some View {
        AdaptiveStack {
            HStack {
                recipientField.frame(maxWidth: isAccessibilitySize ? .infinity : 140).help(ControlHelp.recipient)
                HelpButton(ControlHelp.recipient)
            }
            HStack {
                messageField
                KeyboardDismissButton()
                sendButton.labelStyle(.iconOnly)
            }
        }
        .textFieldStyle(.roundedBorder)
        .onChange(of: model.aprsReplyCount) { isWriting = true }
    }

    private var recipientField: some View {
        // iOS: a phone has room for the short label only.
        #if os(macOS)
            TextField("To (empty: bulletin)", text: $model.aprsRecipient).macName("To")
        #else
            TextField("To", text: $model.aprsRecipient)
        #endif
    }

    private var messageField: some View {
        TextField("Message", text: $model.aprsDraft)
            .macName("Message")
            .focused($isWriting)
            .onSubmit(send)
    }

    private var sendButton: some View {
        Button("Send", systemImage: "paperplane", action: send)
            .disabled(!model.isReady || model.aprsDraft.isEmpty)
    }

    private func send() {
        model.sendAPRSDraft()
    }
}
