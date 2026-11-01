import KV4PTestSupport
import Testing

@testable import KV4PAPRS

/// Checks `APRSEventLog` against java-aprs `AprsController.handle` for packets received over RF.
@Suite("APRS event vectors")
struct APRSEventVectorTests {
    struct Step: Decodable, Sendable {
        let timeMs: Int64
        let frame: String
    }

    struct Input: Decodable, Sendable {
        let steps: [Step]
    }

    struct EventJSON: Decodable, Sendable, Equatable {
        let id: Int64
        let type: Int
        let firstSeenMs: Int64
        let lastSeenMs: Int64
        let packetCount: Int
        let dedupKey: String
        let fromCallsign: String?
        let toCallsign: String?
        let messageIdentifier: String?
        let body: String?
        let positionLat: Double
        let positionLong: Double
        let comment: String?
        let objectName: String?
        let temperature: Double
        let humidity: Double
        let pressure: Double
        let rain: Double
        let snow: Double
        let windForce: Int
        let windDirection: String?
        let relayCallsign: String?
        let internetOnly: Bool
        let deliveryState: Int

        init(_ event: APRSEvent) {
            id = event.id
            type = event.kind.rawValue
            firstSeenMs = event.firstSeenMs
            lastSeenMs = event.lastSeenMs
            packetCount = event.packetCount
            dedupKey = event.dedupKey
            fromCallsign = event.fromCallsign
            toCallsign = event.toCallsign
            messageIdentifier = event.messageIdentifier
            body = event.body
            positionLat = event.latitude
            positionLong = event.longitude
            comment = event.comment
            objectName = event.objectName
            temperature = event.temperature
            humidity = event.humidity
            pressure = event.pressure
            rain = event.rain
            snow = event.snow
            windForce = event.windForce
            windDirection = event.windDirection
            relayCallsign = event.relayCallsign
            internetOnly = false
            deliveryState = 0
        }
    }

    struct Expected: Decodable, Sendable {
        let events: [EventJSON]
        let packets: Int
    }

    static let vectors = (try? VectorFile<Input, Expected>.load("aprs-events", from: .module)) ?? []

    @Test("vector file is present")
    func vectorsPresent() {
        #expect(Self.vectors.count == 3)
    }

    @Test("derives the events Android shows", arguments: vectors)
    func events(vector: VectorFile<Input, Expected>.Vector) throws {
        var log = APRSEventLog()
        for step in vector.input.steps {
            log.receive(try APRSParser.parse(ax25: [UInt8](hex: step.frame)), atMs: step.timeMs)
        }
        #expect(log.events.map(EventJSON.init) == vector.expected.events)
        #expect(log.packetCount == vector.expected.packets)
    }

    @Test(
        "wind directions as compass points",
        arguments: [
            (0, "N"), (11, "N"), (12, "NNE"), (90, "E"), (200, "SSW"), (348, "NNW"), (349, "N"), (-5, "N"),
        ]
    )
    func cardinal(degrees: Int, expected: String) {
        #expect(APRSEventLog.cardinal(degrees) == expected)
    }
}
