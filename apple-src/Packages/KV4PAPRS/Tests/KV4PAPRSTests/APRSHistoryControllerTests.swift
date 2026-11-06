import Foundation
import Testing

@testable import KV4PAPRS

/// What the controller needs for packets that outlive a run of the app (ADR-0057).
@Suite("APRS controller history")
struct APRSHistoryControllerTests {
    private static func controller(_ lines: [String]) -> APRSController {
        var controller = APRSController(startMs: 0)
        controller.callsign = "N0CALL"
        for (index, line) in lines.enumerated() {
            _ = controller.receive(internetLine: line, atMs: Int64(index + 1) * 100_000)
        }
        return controller
    }

    private static let position = "N1CALL>APRS,TCPIP*:=4903.50N/07201.75W>Hello"
    private static let status = "N2CALL>APRS:>Status"
    private static let weather = "N3CALL>APRS:=4903.50N/07201.75W_220/004g005t077r000p010P000h50b09900"
    private static let micE = "N4CALL-7>S32U6T:`(_fn\"Oj/`Hello_3"
    private static let object = "N5CALL>APRS:;TESTOBJ  _111111z4903.50N/07201.75W-Gone"

    @Test("every kind of event survives being stored, with all it shows")
    func codable() throws {
        let events = Self.controller([Self.position, Self.status, Self.weather, Self.micE, Self.object]).events
        #expect(events.count == 5)
        for event in events {
            let data = try JSONEncoder().encode(event)
            #expect(try JSONDecoder().decode(APRSEvent.self, from: data) == event)
        }
    }

    @Test("a symbol that was stored wrongly is refused, not guessed")
    func badSymbol() {
        #expect((try? JSONDecoder().decode(APRSSymbolInfo.self, from: Data("\"/\"".utf8))) == nil)
        #expect(
            (try? JSONDecoder().decode(APRSSymbolInfo.self, from: Data("\"/>\"".utf8)))
                == APRSSymbolInfo(table: "/", code: ">")
        )
    }

    @Test("an event keeps its packet as a line of text")
    func rawLine() throws {
        let received = Self.controller(["N1CALL>APRS,WIDE1-1:>Status"]).events.first
        #expect(received?.rawLine == "N1CALL>APRS,WIDE1-1:>Status")
        let plain = Self.controller([Self.status]).events.first
        #expect(plain?.rawLine == Self.status)

        var controller = Self.controller([])
        controller.txDestination = "APKVPA"
        let beacon = APRSBeacon(latitude: 49, longitude: -72, symbolTable: "/", symbolCode: ">")
        _ = controller.submitBeacon(
            beacon,
            atMs: 1,
            transmit: { _ in .accepted(frequencyHz: 144_800_000, frame: []) },
            gate: { _ in false }
        )
        _ = controller.post(
            to: "N1CALL",
            text: "Hi",
            frequencyHz: nil,
            atMs: 2,
            transmit: { _ in .accepted(frequencyHz: 144_800_000, frame: []) },
            gate: { _ in false }
        )
        #expect(controller.events.allSatisfy { $0.rawLine?.hasPrefix("N0CALL>APKVPA:") == true })
        #expect(controller.events.count == 2)
    }

    @Test("restored events stand first, and new ids do not repeat old ones")
    func restore() {
        var stored = Self.controller([Self.position, Self.status]).events
        stored[1].id = 40
        var controller = APRSController(startMs: 0)
        controller.restore(stored, highestId: 90)
        #expect(controller.events.map(\.id) == [1, 40])
        _ = controller.receive(internetLine: Self.weather, atMs: 1_000_000)
        #expect(controller.events.last?.id == 91)
    }

    @Test("what came before the stored events are back follows them, with a new id")
    func restoreBehindNew() {
        var controller = Self.controller([Self.position])
        let stored = Self.controller([Self.status]).events
        controller.restore(stored, highestId: 7)
        #expect(controller.events.map(\.fromCallsign) == ["N2CALL", "N1CALL"])
        #expect(controller.events.map(\.id) == [1, 8])
        #expect(controller.packets.map(\.eventId) == [8])
    }

    @Test("ids go on from the last one after events have gone")
    func idsAfterRemoval() {
        var controller = Self.controller([Self.position, Self.status])
        controller.removeEvents { $0.id == 1 }
        _ = controller.receive(internetLine: Self.weather, atMs: 1_000_000)
        #expect(controller.events.map(\.id) == [2, 3])
    }

    @Test("a message waiting for its acknowledgement before a restart is not sent again")
    func pendingFails() {
        var controller = Self.controller([])
        controller.txDestination = "APKVPA"
        _ = controller.post(
            to: "N1CALL",
            text: "Hi",
            frequencyHz: nil,
            atMs: 1,
            transmit: { _ in .accepted(frequencyHz: 144_800_000, frame: []) },
            gate: { _ in false }
        )
        var stored = controller.events
        stored[0].deliveryState = .pending
        stored[0].nextRetryAtMs = 2
        var restored = APRSController(startMs: 10)
        restored.restore(stored, highestId: 1)
        #expect(restored.events.first?.deliveryState == .failed)
        #expect(restored.events.first?.nextRetryAtMs == nil)
        var sent = 0
        restored.tick(atMs: 1_000_000) { _ in
            sent += 1
            return .later
        }
        #expect(sent == 0)
    }

    @Test("removed events take their packets along")
    func removal() {
        var controller = Self.controller([Self.position, Self.status])
        #expect(controller.packets.count == 2)
        controller.removeEvents { $0.id == 1 }
        #expect(controller.events.map(\.id) == [2])
        #expect(controller.packets.map(\.eventId) == [2])
    }

    @Test("a removed message gets no acknowledgement any more")
    func removalEndsAcknowledgement() throws {
        var controller = Self.controller([])
        controller.txDestination = "APKVPA"
        let packet = try APRSParser.parse(tnc2: "N1CALL>APRS::N0CALL   :Hello{1")
        _ = controller.receive(
            packet,
            frame: nil,
            frequencyHz: 144_800_000,
            atMs: 1,
            transmit: { _ in .later },
            gate: { _ in false }
        )
        controller.removeEvents { _ in true }
        var sent = 0
        controller.tick(atMs: 1_000_000) { _ in
            sent += 1
            return .later
        }
        #expect(sent == 0)
    }

    @Test("the oldest go when too many are in memory, but no message that still waits, which comes on top")
    func trim() {
        var controller = Self.controller([Self.position, Self.status, Self.weather])
        controller.txDestination = "APKVPA"
        _ = controller.post(
            to: "N1CALL",
            text: "Hi",
            frequencyHz: nil,
            atMs: 1_000_000,
            transmit: { _ in .accepted(frequencyHz: 144_800_000, frame: []) },
            gate: { _ in false }
        )
        let waiting = controller.events.last?.id
        #expect(controller.trim(keeping: 1).map(\.id) == [1, 2])
        #expect(controller.events.map(\.id) == [3, waiting])
        #expect(controller.trim(keeping: 5).isEmpty)
        #expect(controller.events.map(\.id) == [3, waiting])
    }
}
