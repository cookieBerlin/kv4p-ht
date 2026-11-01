import KV4PTestSupport
import Testing

@testable import KV4PAPRS

/// Checks messaging in `APRSController` against java-aprs `AprsController` with a local callsign.
@Suite("APRS messaging vectors")
struct APRSMessagingVectorTests {
    struct Step: Decodable, Sendable {
        let atMs: Int64
        let kind: String
        let frame: String?
        let to: String?
        let text: String?
        let mode: String?
    }

    struct Input: Decodable, Sendable {
        let callsign: String
        let txDestination: String
        let txPath: [String]
        let startMs: Int64
        let steps: [Step]
    }

    struct TransmissionJSON: Decodable, Sendable, Equatable {
        let step: Int
        let purpose: String
        let frequencyHz: Int64?
        let frame: String
        let mode: String
    }

    struct EventJSON: Decodable, Sendable, Equatable {
        let id: Int64
        let type: Int
        let firstSeenMs: Int64
        let lastSeenMs: Int64
        let packetCount: Int
        let fromCallsign: String?
        let toCallsign: String?
        let messageIdentifier: String?
        let body: String?
        let comment: String?
        let deliveryState: Int
        let transmitAttempts: Int
        let nextRetryAtMs: Int64?
        let digipeated: Bool

        init(_ event: APRSEvent) {
            id = event.id
            type = event.kind.rawValue
            firstSeenMs = event.firstSeenMs
            lastSeenMs = event.lastSeenMs
            packetCount = event.packetCount
            fromCallsign = event.fromCallsign
            toCallsign = event.toCallsign
            messageIdentifier = event.messageIdentifier
            body = event.body
            comment = event.comment
            deliveryState = event.deliveryState.rawValue
            transmitAttempts = event.transmitAttempts
            nextRetryAtMs = event.nextRetryAtMs
            digipeated = false
        }
    }

    struct PacketJSON: Decodable, Sendable, Equatable {
        let source: String
        let eventId: Int64?
        let timestampMs: Int64
        let frequencyHz: Int64?
        let path: String?
        let frame: String?

        init(_ record: APRSPacketRecord) {
            source = record.source.rawValue
            eventId = record.eventId
            timestampMs = record.timestampMs
            frequencyHz = record.frequencyHz
            path = record.path
            frame = record.frame.map(Self.hex)
        }

        static func hex(_ bytes: [UInt8]) -> String {
            bytes.map { String($0, radix: 16).count == 1 ? "0" + String($0, radix: 16) : String($0, radix: 16) }
                .joined()
        }
    }

    struct Expected: Decodable, Sendable {
        let results: [Bool?]
        let transmissions: [TransmissionJSON]
        let events: [EventJSON]
        let packets: [PacketJSON]
    }

    static let vectors = (try? VectorFile<Input, Expected>.load("aprs-messaging", from: .module)) ?? []

    @Test("vector file is present")
    func vectorsPresent() {
        #expect(Self.vectors.count == 7)
    }

    @Test("messages, retries and acknowledgements like Android", arguments: vectors)
    func messaging(vector: VectorFile<Input, Expected>.Vector) throws {
        let input = vector.input
        var controller = APRSController(startMs: input.startMs)
        controller.callsign = input.callsign
        controller.txDestination = input.txDestination
        controller.txPath = input.txPath.compactMap(AX25Address.init)
        var mode = "accept"
        var transmissions: [TransmissionJSON] = []
        var results: [Bool?] = []
        for (index, step) in input.steps.enumerated() {
            let transmit = { (request: APRSTransmitRequest) -> APRSTransmitOutcome in
                let frame = (try? request.packet.ax25Frame()) ?? []
                transmissions.append(
                    TransmissionJSON(
                        step: index,
                        purpose: request.purpose.rawValue,
                        frequencyHz: request.frequencyHz,
                        frame: PacketJSON.hex(frame),
                        mode: mode
                    )
                )
                switch mode {
                case "refuse": return .later
                case "terminal": return .never
                default: return .accepted(frequencyHz: request.frequencyHz ?? 144_390_000, frame: frame)
                }
            }
            var result: Bool?
            switch step.kind {
            case "rx":
                let frame = try [UInt8](hex: try #require(step.frame))
                controller.receive(
                    try APRSParser.parse(ax25: frame),
                    frame: frame,
                    frequencyHz: 144_390_000,
                    atMs: step.atMs,
                    transmit: transmit,
                    gate: { _ in false }
                )
            case "post":
                result = controller.post(
                    to: try #require(step.to),
                    text: try #require(step.text),
                    frequencyHz: 144_390_000,
                    atMs: step.atMs,
                    transmit: transmit,
                    gate: { _ in false }
                )
            case "tick":
                controller.tick(atMs: step.atMs, transmit: transmit)
            default:
                mode = try #require(step.mode)
            }
            results.append(result)
        }
        #expect(results == vector.expected.results)
        #expect(transmissions == vector.expected.transmissions)
        #expect(controller.events.map(EventJSON.init) == vector.expected.events)
        #expect(controller.packets.map(PacketJSON.init) == vector.expected.packets)
    }

    @Test("callsigns are normalised like setCallsign")
    func normalisedCallsign() {
        var controller = APRSController(startMs: 0)
        controller.callsign = " n0call-7 "
        controller.txDestination = " apkvpa "
        #expect(controller.callsign == "N0CALL-7")
        #expect(controller.txDestination == "APKVPA")
    }

    @Test("without a callsign or destination nothing is posted")
    func notConfigured() {
        var controller = APRSController(startMs: 0)
        let refuse = { (_: APRSTransmitRequest) -> APRSTransmitOutcome in .never }
        let withoutCallsign = controller.post(
            to: "N1CALL",
            text: "x",
            frequencyHz: nil,
            atMs: 0,
            transmit: refuse,
            gate: { _ in false }
        )
        controller.callsign = "N0CALL"
        let withoutDestination = controller.post(
            to: "N1CALL",
            text: "x",
            frequencyHz: nil,
            atMs: 0,
            transmit: refuse,
            gate: { _ in false }
        )
        #expect(!withoutCallsign)
        #expect(!withoutDestination)
    }

    @Test("an identifier still pending for the same station is skipped")
    func identifierCollision() {
        var controller = APRSController(startMs: 35)
        controller.callsign = "N0CALL"
        controller.txDestination = "APKVPA"
        let accept = { (request: APRSTransmitRequest) -> APRSTransmitOutcome in
            .accepted(frequencyHz: 1, frame: (try? request.packet.ax25Frame()) ?? [])
        }
        _ = controller.post(to: "N1CALL", text: "a", frequencyHz: nil, atMs: 0, transmit: accept, gate: { _ in false })
        controller.nextMessageIdentifier = 35
        _ = controller.post(to: "N1CALL", text: "b", frequencyHz: nil, atMs: 0, transmit: accept, gate: { _ in false })
        _ = controller.post(to: "N2CALL", text: "c", frequencyHz: nil, atMs: 0, transmit: accept, gate: { _ in false })
        #expect(controller.events.map(\.messageIdentifier) == ["Z", "10", "11"])
    }

    @Test("an acknowledgement relayed in a third-party packet is no event")
    func thirdPartyAcknowledgement() throws {
        var controller = APRSController(startMs: 0)
        let packet = try APRSParser.parse(tnc2: "N1CALL>APRS:}N2CALL>APRS,TCPIP,N1CALL*::N0CALL   :ack1")
        let event = controller.receive(
            packet,
            frame: nil,
            frequencyHz: nil,
            atMs: 0,
            transmit: { _ in .never },
            gate: { _ in false }
        )
        #expect(event == nil)
        #expect(controller.packets.count == 1)
    }

    @Test("addresses compare without SSID 0, like normalizeAx25Address")
    func addresses() {
        #expect(APRSController.address(" n0call ") == "N0CALL")
        #expect(APRSController.address("N0CALL-0") == "N0CALL")
        #expect(APRSController.address("N0CALL-07") == "N0CALL-7")
        #expect(APRSController.address("N0CALL-X") == "N0CALL-X")
    }
}
