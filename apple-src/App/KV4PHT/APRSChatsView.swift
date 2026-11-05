import KV4PAPRS
import KV4PRadio
import SwiftUI

/// The chats with other stations, and one of them when it is open (ADR-0061). In place rather than in a navigation
/// stack, as the APRS page sits in one on a wide iPad.
struct APRSChatsView: View {
    @Bindable var model: RadioViewModel

    var body: some View {
        if let peer = model.openChat {
            APRSConversationView(model: model, peer: peer)
        } else {
            list
        }
    }

    private var list: some View {
        List {
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

/// One chat, in the order it was written: this station's messages on the right, with their delivery.
private struct APRSConversationView: View {
    let model: RadioViewModel
    let peer: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Chats", systemImage: "chevron.left") { model.openChat = nil }
                Spacer()
                Text(peer).font(.headline)
                Spacer()
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
        }
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
                HStack(spacing: 4) {
                    Text(Date(timeIntervalSince1970: Double(event.firstSeenMs) / 1000), style: .time)
                    if let state = APRSPacketList.delivery(event.deliveryState) {
                        Label(state.0, systemImage: state.1).labelStyle(.iconOnly).help(state.0)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            if !isMine { Spacer(minLength: 40) }
        }
    }
}
