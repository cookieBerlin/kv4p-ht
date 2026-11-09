import Foundation
import Testing

@testable import KV4PAPRS

/// Chats as a view of the messages to and from this station (ADR-0061).
@Suite("APRS chats")
struct APRSChatsTests {
    private static func event(_ line: String, atMs ms: Int64 = 1_000) -> APRSEvent {
        var controller = APRSController(startMs: 0)
        _ = controller.receive(internetLine: line, atMs: ms)
        return controller.events[0]
    }

    @Test("the other station is the sender of a message to this one, or the recipient of its own, with its SSID")
    func peers() {
        #expect(Self.event("N1CALL-7>APRS::N0CALL   :Hi").chatPeer(ownCallsign: "N0CALL") == "N1CALL-7")
        #expect(Self.event("N1CALL>APRS::N0CALL-9 :Hi").chatPeer(ownCallsign: "n0call") == "N1CALL")
        #expect(Self.event("N0CALL>APRS::n1call-5 :Hi").chatPeer(ownCallsign: "N0CALL") == "N1CALL-5")
        #expect(Self.event("N0CALL-9>APRS::N1CALL   :Hi").chatPeer(ownCallsign: "N0CALL") == "N1CALL")
    }

    @Test("this station's other SSIDs are chats of their own")
    func ownSSIDs() {
        #expect(Self.event("N0CALL>APRS::N0CALL-7 :Hi").chatPeer(ownCallsign: "N0CALL") == "N0CALL-7")
        #expect(Self.event("N0CALL-7>APRS::N0CALL   :Hi").chatPeer(ownCallsign: "N0CALL") == "N0CALL-7")
    }

    @Test("bulletins, messages between others, other packets and a missing callsign are no chat")
    func noChat() {
        #expect(Self.event("N0CALL>APRS::BLN1CQ   :Hi").chatPeer(ownCallsign: "N0CALL") == nil)
        #expect(Self.event("N1CALL>APRS::QST      :Hi").chatPeer(ownCallsign: "N0CALL") == nil)
        #expect(Self.event("N1CALL>APRS::N2CALL   :Hi").chatPeer(ownCallsign: "N0CALL") == nil)
        #expect(Self.event("N1CALL>APRS:>Status").chatPeer(ownCallsign: "N0CALL") == nil)
        #expect(Self.event("N1CALL>APRS::N0CALL   :Hi").chatPeer(ownCallsign: "") == nil)
    }

    @Test("chats are grouped by station, newest first, with their last message and what is unread")
    func conversations() {
        let first = Self.event("N1CALL>APRS::N0CALL   :One", atMs: 1_000)
        let second = Self.event("N1CALL>APRS::N0CALL   :Two", atMs: 3_000)
        let mine = Self.event("N0CALL>APRS::N1CALL   :Mine", atMs: 4_000)
        let other = Self.event("N2CALL>APRS::N0CALL   :Other", atMs: 2_000)
        let noise = Self.event("N3CALL>APRS::N4CALL   :Noise", atMs: 5_000)
        let chats = APRSChats.conversations(
            in: [first, second, mine, other, noise],
            ownCallsign: "N0CALL",
            readUntilMs: ["N1CALL": 1_000]
        )
        #expect(chats.map(\.peer) == ["N1CALL", "N2CALL"])
        #expect(chats[0].last.body == "Mine")
        #expect(chats[0].unread == 1)
        #expect(chats[1].unread == 1)
        #expect(chats.map(\.id) == ["N1CALL", "N2CALL"])
    }

    @Test("the messages of a chat come in the order they were written")
    func messages() {
        var later = Self.event("N1CALL>APRS::N0CALL   :Later", atMs: 2_000)
        later.id = 1
        var earlier = Self.event("N0CALL>APRS::N1CALL   :Earlier", atMs: 1_000)
        earlier.id = 2
        let other = Self.event("N2CALL>APRS::N0CALL   :Other", atMs: 500)
        #expect(
            APRSChats.messages(with: "N1CALL", in: [later, earlier, other], ownCallsign: "N0CALL").map(\.body) == [
                "Earlier", "Later",
            ]
        )
    }

    @Test("a message of the same moment keeps the order of its id")
    func sameMoment() {
        var one = Self.event("N1CALL>APRS::N0CALL   :One")
        one.id = 1
        var two = Self.event("N1CALL>APRS::N0CALL   :Two")
        two.id = 2
        #expect(
            APRSChats.messages(with: "N1CALL", in: [two, one], ownCallsign: "N0CALL").map(\.body) == ["One", "Two"]
        )
        #expect(APRSChats.conversations(in: [two, one], ownCallsign: "N0CALL", readUntilMs: [:])[0].last.body == "Two")
    }
}

/// Writing in chats (ADR-0061, 4.7b).
@Suite("APRS chats: writing")
struct APRSChatWritingTests {
    @Test("a message to a station leaves room for its number, so that nothing is cut off; a bulletin has 67")
    func textLimit() {
        #expect(APRSChats.textLimit(to: "N1CALL") == 61)
        #expect(APRSChats.textLimit(to: "BLN1CQ") == 67)
        let text = String(repeating: "x", count: 61)
        let payload = String(
            decoding: MessageField.payload(to: "N1CALL", text: text, identifier: "ZZZZZ"),
            as: UTF8.self
        )
        #expect(payload.contains(text + "{ZZZZZ"))
    }

    @Test("a callsign for a new chat is cleaned up, and what cannot be one is refused")
    func callsigns() {
        #expect(APRSChats.callsign(from: " n1call-7 ") == "N1CALL-7")
        #expect(APRSChats.callsign(from: "N1CALL") == "N1CALL")
        #expect(APRSChats.callsign(from: "N1") == nil)
        #expect(APRSChats.callsign(from: "N1CALLXX") == nil)
        #expect(APRSChats.callsign(from: "N1CALL-123") == nil)
        #expect(APRSChats.callsign(from: "N1 CALL") == nil)
        #expect(APRSChats.callsign(from: "BLN1CQ") == nil)
        #expect(APRSChats.callsign(from: "") == nil)
    }

    @Test("a message sent again leaves the chat, but stays a packet, also when stored")
    func resent() throws {
        var controller = APRSController(startMs: 0)
        controller.callsign = "N0CALL"
        controller.txDestination = "APKVPA"
        _ = controller.post(
            to: "N1CALL",
            text: "Hi",
            frequencyHz: nil,
            atMs: 1,
            transmit: { _ in .accepted(frequencyHz: 144_800_000, frame: []) },
            gate: { _ in false }
        )
        let id = controller.events[0].id
        #expect(!controller.events[0].isResent)
        controller.markResent(id: id)
        controller.markResent(id: 999)
        #expect(controller.events[0].isResent)
        #expect(APRSChats.conversations(in: controller.events, ownCallsign: "N0CALL", readUntilMs: [:]).isEmpty)
        #expect(APRSChats.messages(with: "N1CALL", in: controller.events, ownCallsign: "N0CALL").isEmpty)
        let data = try JSONEncoder().encode(controller.events[0])
        #expect(try JSONDecoder().decode(APRSEvent.self, from: data).isResent)
        var older = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        older["isResentMark"] = nil
        let decoded = try JSONDecoder().decode(APRSEvent.self, from: JSONSerialization.data(withJSONObject: older))
        #expect(!decoded.isResent)
    }
}
