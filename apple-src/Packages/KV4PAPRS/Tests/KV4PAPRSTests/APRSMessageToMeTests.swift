import Testing

@testable import KV4PAPRS

/// Which messages are meant for this station (ADR-0058).
@Suite("APRS messages to this station")
struct APRSMessageToMeTests {
    private static func event(_ line: String) -> APRSEvent {
        var controller = APRSController(startMs: 0)
        _ = controller.receive(internetLine: line, atMs: 1_000)
        return controller.events[0]
    }

    @Test("a message to this callsign counts, with any SSID and in any case")
    func toMe() {
        #expect(Self.event("N1CALL>APRS::N0CALL   :Hi").isMessage(to: "N0CALL"))
        #expect(Self.event("N1CALL>APRS::N0CALL-7 :Hi").isMessage(to: "n0call-9"))
    }

    @Test("what is not a message to this station does not count")
    func notToMe() {
        #expect(!Self.event("N1CALL>APRS::N2CALL   :Hi").isMessage(to: "N0CALL"))
        #expect(!Self.event("N1CALL>APRS::BLN1CQ   :Hi").isMessage(to: "N0CALL"))
        #expect(!Self.event("N1CALL>APRS:>Status").isMessage(to: "N0CALL"))
        #expect(!Self.event("N1CALL>APRS::N0CALL   :Hi").isMessage(to: " "))
    }

    @Test("this station's own message to itself does not count, but one from another of its SSIDs does")
    func fromMe() {
        #expect(!Self.event("N0CALL>APRS::N0CALL-7 :Hi").isMessage(to: "n0call"))
        #expect(Self.event("N0CALL-9>APRS::N0CALL-7 :Hi").isMessage(to: "N0CALL"))
    }
}
