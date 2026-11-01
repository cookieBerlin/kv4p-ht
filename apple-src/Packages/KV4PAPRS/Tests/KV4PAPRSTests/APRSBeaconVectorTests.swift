import KV4PTestSupport
import Testing

@testable import KV4PAPRS

/// Checks position beacons and digipeating in `APRSController` against java-aprs.
@Suite("APRS beacon and digipeating vectors")
struct APRSBeaconVectorTests {
    struct BeaconInput: Decodable, Sendable {
        let latitude: Double?
        let longitude: Double?
        let longitudeIsNaN: Bool
        let symbolTable: String?
        let symbolCode: String?
        let messagingCapable: Bool
        let compressed: Bool
        let altitudeMeters: Double?
        let speedKnots: Double?
        let courseDegrees: Int?
        let comment: String?
        let startMs: Int64
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
        let packetCount: Int
        let dedupKey: String
        let fromCallsign: String?
        let positionLat: Double
        let positionLong: Double
        let comment: String?
        let digipeated: Bool?

        init(_ event: APRSEvent, digipeated: Bool?) {
            id = event.id
            type = event.kind.rawValue
            packetCount = event.packetCount
            dedupKey = event.dedupKey
            fromCallsign = event.fromCallsign
            positionLat = event.latitude
            positionLong = event.longitude
            comment = event.comment
            self.digipeated = digipeated.map { _ in event.isDigipeated }
        }
    }

    struct BeaconExpected: Decodable, Sendable {
        let accepted: Bool
        let transmissions: [TransmissionJSON]
        let events: [EventJSON]
        let packets: Int
    }

    struct Step: Decodable, Sendable {
        let atMs: Int64
        let kind: String
        let frame: String?
        let mode: String?
    }

    struct DigipeatInput: Decodable, Sendable {
        let startMs: Int64
        let steps: [Step]
    }

    struct DigipeatExpected: Decodable, Sendable {
        let transmissions: [TransmissionJSON]
        let events: [EventJSON]
        let packets: Int
    }

    static let beacons = (try? VectorFile<BeaconInput, BeaconExpected>.load("aprs-beacons", from: .module)) ?? []
    static let digipeating =
        (try? VectorFile<DigipeatInput, DigipeatExpected>.load("aprs-digipeating", from: .module)) ?? []

    static func controller(startMs: Int64) -> APRSController {
        var controller = APRSController(startMs: startMs)
        controller.callsign = "N0CALL"
        controller.txDestination = "APKVPA"
        return controller
    }

    /// The generator's transport: records every request and answers by `mode`.
    final class Transmitter {
        var mode = "accept"
        var step = 0
        var transmissions: [TransmissionJSON] = []

        func transmit(_ request: APRSTransmitRequest) -> APRSTransmitOutcome {
            let frame = (try? request.packet.ax25Frame()) ?? []
            transmissions.append(
                TransmissionJSON(
                    step: step,
                    purpose: request.purpose.rawValue,
                    frequencyHz: request.frequencyHz,
                    frame: APRSMessagingVectorTests.PacketJSON.hex(frame),
                    mode: mode
                )
            )
            return mode == "refuse" ? .later : .accepted(frequencyHz: request.frequencyHz ?? 144_390_000, frame: frame)
        }
    }

    @Test("vector files are present")
    func vectorsPresent() {
        #expect(Self.beacons.count == 15)
        #expect(Self.digipeating.count == 2)
    }

    @Test("position beacons like Android", arguments: beacons)
    func beacon(vector: VectorFile<BeaconInput, BeaconExpected>.Vector) {
        let input = vector.input
        var controller = Self.controller(startMs: input.startMs)
        controller.txPath = ["WIDE1-1", "WIDE2-1"].compactMap(AX25Address.init)
        let beacon = APRSBeacon(
            latitude: input.latitude ?? .nan,
            longitude: input.longitudeIsNaN ? .nan : input.longitude ?? .nan,
            symbolTable: input.symbolTable?.unicodeScalars.first.map(Character.init),
            symbolCode: input.symbolCode?.unicodeScalars.first.map(Character.init),
            isMessagingCapable: input.messagingCapable,
            isCompressed: input.compressed,
            altitudeMeters: input.altitudeMeters,
            speedKnots: input.speedKnots,
            courseDegrees: input.courseDegrees,
            comment: input.comment
        )
        let transmitter = Transmitter()
        let accepted = controller.submitBeacon(
            beacon,
            atMs: input.startMs,
            transmit: transmitter.transmit,
            gate: { _ in false }
        )
        #expect(accepted == vector.expected.accepted)
        #expect(transmitter.transmissions == vector.expected.transmissions)
        #expect(controller.events.map { EventJSON($0, digipeated: nil) } == vector.expected.events)
        #expect(controller.packets.count == vector.expected.packets)
    }

    @Test("digipeating like Android", arguments: digipeating)
    func digipeat(vector: VectorFile<DigipeatInput, DigipeatExpected>.Vector) throws {
        var controller = Self.controller(startMs: vector.input.startMs)
        controller.isDigipeatingEnabled = true
        let transmitter = Transmitter()
        for step in vector.input.steps {
            if step.kind == "rx" {
                let frame = try [UInt8](hex: try #require(step.frame))
                controller.receive(
                    try APRSParser.parse(ax25: frame),
                    frame: frame,
                    frequencyHz: 144_390_000,
                    atMs: step.atMs,
                    transmit: transmitter.transmit,
                    gate: { _ in false }
                )
            } else {
                transmitter.mode = try #require(step.mode)
            }
            transmitter.step += 1
        }
        #expect(transmitter.transmissions == vector.expected.transmissions)
        #expect(controller.events.map { EventJSON($0, digipeated: true) } == vector.expected.events)
        #expect(controller.packets.count == vector.expected.packets)
    }

    @Test("a new callsign forgets what was digipeated")
    func callsignClearsCaches() throws {
        var controller = Self.controller(startMs: 0)
        controller.isDigipeatingEnabled = true
        let transmitter = Transmitter()
        let packet = try APRSParser.parse(tnc2: "N1CALL>APRS,WIDE1-1:>x")
        controller.receive(
            packet,
            frame: nil,
            frequencyHz: nil,
            atMs: 0,
            transmit: transmitter.transmit,
            gate: { _ in false }
        )
        controller.callsign = "N0CALL"
        controller.receive(
            packet,
            frame: nil,
            frequencyHz: nil,
            atMs: 1,
            transmit: transmitter.transmit,
            gate: { _ in false }
        )
        controller.callsign = "N2CALL"
        controller.receive(
            packet,
            frame: nil,
            frequencyHz: nil,
            atMs: 2,
            transmit: transmitter.transmit,
            gate: { _ in false }
        )
        #expect(transmitter.transmissions.count == 2)
    }

    @Test("an acknowledgement for another station is repeated without an event")
    func digipeatWithoutEvent() throws {
        var controller = Self.controller(startMs: 0)
        controller.isDigipeatingEnabled = true
        let transmitter = Transmitter()
        let packet = try APRSParser.parse(tnc2: "N1CALL>APRS,WIDE1-1::N2CALL   :ack1")
        let event = controller.receive(
            packet,
            frame: nil,
            frequencyHz: nil,
            atMs: 0,
            transmit: transmitter.transmit,
            gate: { _ in false }
        )
        #expect(event == nil)
        #expect(transmitter.transmissions.count == 1)
        #expect(controller.packets.map(\.source) == [.rxRF, .txRF])
    }
}
