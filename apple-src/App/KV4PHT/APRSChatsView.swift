import KV4PAPRS
import KV4PRadio
import SwiftUI

/// The chats with other stations, and one of them when it is open (ADR-0061). In place rather than in a navigation
/// stack, as the APRS page sits in one on a wide iPad.
struct APRSChatsView: View {
    @Bindable var model: RadioViewModel
    @State private var isStartingChat = false
    @State private var newCallsign = ""

    var body: some View {
        if let peer = model.openChat {
            APRSConversationView(model: model, peer: peer)
        } else {
            list
        }
    }

    private var list: some View {
        List {
            if model.canSendOnAir {
                Button("New chat", systemImage: "plus") {
                    newCallsign = ""
                    isStartingChat = true
                }
            }
            if !model.isKeepingPackets {
                Label("Keep packets is off, so chats end with the app.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.conversations) { conversation in
                Button {
                    model.aprsRecipient = conversation.peer
                    model.openChat = conversation.peer
                } label: {
                    row(conversation)
                }
                .buttonStyle(.plain)
            }
        }
        .alert("New chat", isPresented: $isStartingChat) {
            TextField("Callsign", text: $newCallsign)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Open") {
                if let peer = APRSChats.callsign(from: newCallsign) {
                    model.aprsRecipient = peer
                    model.openChat = peer
                }
            }
            .disabled(APRSChats.callsign(from: newCallsign) == nil)
        } message: {
            Text("The callsign with its SSID, if it has one, as a reply goes to exactly that one.")
        }
        .overlay {
            if model.conversations.isEmpty {
                ContentUnavailableView(
                    "No chats yet",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Messages to and from your callsign show here, one chat for each station.")
                )
            }
        }
    }

    private func row(_ conversation: APRSConversation) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.peer).font(.headline)
                Text(conversation.last.body ?? "")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(Date(timeIntervalSince1970: Double(conversation.last.lastSeenMs) / 1000), style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if conversation.unread > 0 {
                    Text(conversation.unread, format: .number)
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .background(.tint, in: .capsule)
                        .accessibilityLabel("\(conversation.unread) unread")
                }
            }
        }
        .contentShape(.rect)
    }
}

/// One chat, in the order it was written: this station's messages on the right, with their delivery, and a line to
/// write below.
private struct APRSConversationView: View {
    let model: RadioViewModel
    let peer: String
    @State private var text = ""
    @State private var isConfirmingDelete = false
    @FocusState private var isWriting: Bool

    private var limit: Int { model.chatTextLimit(for: peer) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Chats", systemImage: "chevron.left") { model.openChat = nil }
                Spacer()
                Text(peer).font(.headline)
                Spacer()
                Button("Delete chat…", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
                    .labelStyle(.iconOnly)
            }
            .padding(8)
            Divider()
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(model.messages(with: peer)) { bubble($0) }
                }
                .padding(8)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .overlay {
                if model.messages(with: peer).isEmpty {
                    ContentUnavailableView(
                        "No messages yet",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text(
                            "Messages go over the radio. A station only on the internet gets them if an iGate passes them on."
                        )
                    )
                }
            }
            Divider()
            input
        }
        .alert("Delete the chat with \(peer)?", isPresented: $isConfirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { model.deleteChat(with: peer) }
        } message: {
            Text("This also removes its messages from the packets.")
        }
    }

    @ViewBuilder private var input: some View {
        if model.canSendOnAir {
            HStack {
                TextField("Message", text: $text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .focused($isWriting)
                    .onSubmit(send)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { isWriting = false }
                        }
                    }
                    .onChange(of: text) {
                        // A stop rather than a cut when it is sent, so that nothing goes missing.
                        if text.count > limit { text = String(text.prefix(limit)) }
                    }
                Text("\(text.count)/\(limit)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(text.count == limit ? .red : .secondary)
                    .accessibilityLabel("\(limit - text.count) characters left")
                Button("Send", systemImage: "paperplane", action: send)
                    .labelStyle(.iconOnly)
                    .disabled(!model.isReady || text.isEmpty)
            }
            .padding(8)
            if !model.isReady {
                Text("Connect the radio to send.").font(.footnote).foregroundStyle(.secondary).padding(.bottom, 8)
            }
        } else if let blocked = model.transmitBlockedText {
            Text(blocked).font(.footnote).foregroundStyle(.secondary).padding(8)
        }
    }

    private func send() {
        guard !text.isEmpty, model.isReady else { return }
        model.sendChatMessage(text, to: peer)
        text = ""
    }

    private func bubble(_ event: APRSEvent) -> some View {
        let isMine = event.fromCallsign.uppercased() != peer
        return HStack {
            if isMine { Spacer(minLength: 40) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
                Text(event.body ?? "")
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        isMine ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(.fill.tertiary),
                        in: .rect(cornerRadius: 12)
                    )
                    .textSelection(.enabled)
                    .contextMenu {
                        if model.canResend(event) {
                            Button("Send again", systemImage: "arrow.clockwise") { model.resend(event) }
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) { model.deleteAPRSEvent(event) }
                    }
                HStack(spacing: 4) {
                    Text(Date(timeIntervalSince1970: Double(event.firstSeenMs) / 1000), style: .time)
                    if let state = APRSPacketList.delivery(event.deliveryState) {
                        Label(state.0, systemImage: state.1).labelStyle(.iconOnly).help(state.0)
                    }
                    if model.canResend(event) {
                        Button("Send again") { model.resend(event) }
                            .buttonStyle(.borderless)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            if !isMine { Spacer(minLength: 40) }
        }
    }
}
