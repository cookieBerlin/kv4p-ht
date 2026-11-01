import KV4PTestSupport
import Testing

@testable import KV4PAPRS

/// Android `AprsFeedPolicy`: the APRS tab shows all events, or only the messages for this station.
@Suite("APRS feed filter vectors")
struct APRSFeedFilterVectorTests {
    struct Input: Decodable, Sendable {
        let type: Int
        let from: String?
        let to: String?
        let callsign: String?
    }

    struct Expected: Decodable, Sendable {
        let visible: Bool
    }

    static let vectors = (try? VectorFile<Input, Expected>.load("aprs-feed-filter", from: .module)) ?? []

    @Test("vector file is present")
    func vectorsPresent() {
        #expect(Self.vectors.count == 17)
    }

    @Test("only mine: messages from or to this station, to everyone or bulletins; all other events", arguments: vectors)
    func mine(vector: VectorFile<Input, Expected>.Vector) throws {
        var event = APRSEvent(firstSeenMs: 0, lastSeenMs: 0, fromCallsign: vector.input.from ?? "")
        event.kind = try #require(APRSEvent.Kind(rawValue: vector.input.type))
        event.toCallsign = vector.input.to
        let callsign = vector.input.callsign ?? ""
        #expect(APRSDestinationFilter.mine.shows(event, callsign: callsign) == vector.expected.visible)
        #expect(APRSDestinationFilter.all.shows(event, callsign: callsign))
    }
}
