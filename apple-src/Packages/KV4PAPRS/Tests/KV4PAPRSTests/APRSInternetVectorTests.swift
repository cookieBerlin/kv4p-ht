import KV4PTestSupport
import Testing

@testable import KV4PAPRS

/// Checks APRS-IS and the iGate in `APRSController` against java-aprs.
@Suite("APRS-IS vectors")
struct APRSInternetVectorTests {
    struct Step: Decodable, Sendable {
        let atMs: Int64
        let kind: String
        let frame: String?
        let line: String?
        let to: String?
        let text: String?
        let mode: String?
    }

    struct Input: Decodable, Sendable {
        let startMs: Int64
        let steps: [Step]
    }

    struct LineJSON: Decodable, Sendable, Equatable {
        let step: Int
        let line: String
        let mode: String
    }

    struct EventJSON: Decodable, Sendable, Equatable {
        let id: Int64
        let type: Int
        let packetCount: Int
        let fromCallsign: String?
        let comment: String?
        let body: String?
        let internetOnly: Bool
        let deliveryState: Int

        init(_ event: APRSEvent) {
            id = event.id
            type = event.kind.rawValue
            packetCount = event.packetCount
            fromCallsign = event.fromCallsign
            comment = event.comment
            body = event.body
            internetOnly = event.isInternetOnly
            deliveryState = event.deliveryState.rawValue
        }
    }

    struct PacketJSON: Decodable, Sendable, Equatable {
        let source: String
        let eventId: Int64?
        let timestampMs: Int64
        let frequencyHz: Int64?
        let path: String?
        let tnc2: String?

        init(_ record: APRSPacketRecord) {
            source = record.source.rawValue
            eventId = record.eventId
            timestampMs = record.timestampMs
            frequencyHz = record.frequencyHz
            path = record.path
            tnc2 = record.tnc2
        }
    }

    struct Expected: Decodable, Sendable {
        let transmissions: [APRSBeaconVectorTests.TransmissionJSON]
        let internetLines: [LineJSON]
        let events: [EventJSON]
        let packets: [PacketJSON]
    }

    /// The generator's APRS-IS link: in `accept` mode it queues lines and confirms them after the step; any other
    /// mode refuses them.
    final class Internet {
        var mode = "accept"
        var step = 0
        var lines: [LineJSON] = []
        var queued: [APRSInternetRequest] = []

        func send(_ request: APRSInternetRequest) -> Bool {
            lines.append(LineJSON(step: step, line: request.line, mode: mode))
            guard mode == "accept" else { return false }
            queued.append(request)
            return true
        }
    }

    static let vectors = (try? VectorFile<Input, Expected>.load("aprs-internet", from: .module)) ?? []

    @Test("vector file is present")
    func vectorsPresent() {
        #expect(Self.vectors.count == 2)
    }

    @Test("iGate and APRS-IS like Android", arguments: vectors)
    func internet(vector: VectorFile<Input, Expected>.Vector) throws {
        var controller = APRSBeaconVectorTests.controller(startMs: vector.input.startMs)
        controller.txPath = ["WIDE1-1", "WIDE2-1"].compactMap(AX25Address.init)
        controller.isIGateEnabled = true
        let radio = APRSBeaconVectorTests.Transmitter()
        let internet = Internet()
        for step in vector.input.steps {
            switch step.kind {
            case "rx":
                let frame = try [UInt8](hex: try #require(step.frame))
                controller.receive(
                    try APRSParser.parse(ax25: frame),
                    frame: frame,
                    frequencyHz: 144_390_000,
                    atMs: step.atMs,
                    transmit: radio.transmit,
                    gate: internet.send
                )
            case "is":
                controller.receive(internetLine: try #require(step.line), atMs: step.atMs)
            case "post":
                _ = controller.post(
                    to: try #require(step.to),
                    text: try #require(step.text),
                    frequencyHz: 144_390_000,
                    atMs: step.atMs,
                    transmit: radio.transmit,
                    gate: internet.send
                )
            case "beacon":
                let beacon = APRSBeacon(latitude: 49.0583, longitude: -72.0292, symbolTable: "/", symbolCode: "$")
                _ = controller.submitBeacon(beacon, atMs: step.atMs, transmit: radio.transmit, gate: internet.send)
            case "tick":
                controller.tick(atMs: step.atMs, transmit: radio.transmit)
            case "mode":
                radio.mode = try #require(step.mode)
            case "net":
                internet.mode = try #require(step.mode)
            default:
                controller.isIGateEnabled = step.mode == "on"
            }
            for request in internet.queued {
                controller.recordInternetTransmission(request, atMs: step.atMs)
            }
            internet.queued = []
            radio.step += 1
            internet.step += 1
        }
        #expect(radio.transmissions == vector.expected.transmissions)
        #expect(internet.lines == vector.expected.internetLines)
        #expect(controller.events.map(EventJSON.init) == vector.expected.events)
        #expect(controller.packets.map(PacketJSON.init) == vector.expected.packets)
    }
}
