/// A chat with one station (ADR-0061): a view of the stored messages, which needs no storage of its own.
public struct APRSConversation: Equatable, Identifiable, Sendable {
    /// The other station, with its SSID, as a reply must reach that one.
    public let peer: String
    public let last: APRSEvent
    /// Messages from the other station that came after it was last read.
    public let unread: Int

    public var id: String { peer }
}

extension APRSEvent {
    /// The other station of a message to or from this one, with any SSID of this one; `nil` for anything else, also for
    /// a message to everyone.
    public func chatPeer(ownCallsign: String) -> String? {
        guard !isResent, isMessage(of: ownCallsign), let to = toCallsign, APRSController.requiresAcknowledgement(to)
        else {
            return nil
        }
        let own = Java.trim(ownCallsign).uppercased()
        let from = fromCallsign.uppercased()
        if from != own, Self.baseCallsign(to) == Self.baseCallsign(own) {
            return from
        }
        return Java.trim(to).uppercased()
    }
}

public enum APRSChats {
    /// Newest first. `readUntilMs` holds when each chat was last read.
    public static func conversations(
        in events: [APRSEvent],
        ownCallsign: String,
        readUntilMs: [String: Int64]
    ) -> [APRSConversation] {
        let byPeer = Dictionary(grouping: events) { $0.chatPeer(ownCallsign: ownCallsign) }
        return byPeer.compactMap { peer, messages -> APRSConversation? in
            guard let peer, let last = messages.max(by: isEarlier) else { return nil }
            let readUntil = readUntilMs[peer] ?? 0
            let unread = messages.filter { $0.fromCallsign.uppercased() == peer && $0.firstSeenMs > readUntil }
            return APRSConversation(peer: peer, last: last, unread: unread.count)
        }
        .sorted { isEarlier($1.last, $0.last) }
    }

    /// In the order they were written.
    public static func messages(with peer: String, in events: [APRSEvent], ownCallsign: String) -> [APRSEvent] {
        events.filter { $0.chatPeer(ownCallsign: ownCallsign) == peer }.sorted(by: isEarlier)
    }

    /// How much text a message to `recipient` can hold without being cut: one that is acknowledged also carries its
    /// number of up to five characters after a `{`.
    public static func textLimit(to recipient: String) -> Int {
        APRSController.requiresAcknowledgement(recipient) ? 61 : 67
    }

    /// A callsign as a chat can start with, in upper case; `nil` for what cannot be one, also for a bulletin.
    public static func callsign(from text: String) -> String? {
        let callsign = Java.trim(text).uppercased()
        guard callsign.wholeMatch(of: /[A-Z0-9]{3,6}(-[A-Z0-9]{1,2})?/) != nil,
            APRSController.requiresAcknowledgement(callsign)
        else { return nil }
        return callsign
    }

    private static func isEarlier(_ first: APRSEvent, _ second: APRSEvent) -> Bool {
        (first.firstSeenMs, first.id) < (second.firstSeenMs, second.id)
    }
}
