import KV4PTestSupport
import Testing

@testable import KV4PAPRS

/// Checks the APRS-IS login helpers against java-aprs `AprsIsClient`.
@Suite("APRS-IS login vectors")
struct APRSISLoginVectorTests {
    struct Input: Decodable, Sendable {
        let kind: String
        let callsign: String?
        let passcode: Int?
        let receive: Bool?
        let latitude: Double?
        let longitude: Double?
        let longitudeIsNaN: Bool?
        let radiusKm: Double?
        let server: String?
    }

    struct Expected: Decodable, Sendable {
        let passcode: Int?
        let line: String?
        let normalized: String?
    }

    static let vectors = (try? VectorFile<Input, Expected>.load("aprs-is-login", from: .module)) ?? []

    @Test("vector file is present")
    func vectorsPresent() {
        #expect(Self.vectors.count == 25)
    }

    @Test("passcode, login line and server like Android", arguments: vectors)
    func login(vector: VectorFile<Input, Expected>.Vector) throws {
        let input = vector.input
        switch input.kind {
        case "passcode":
            #expect(APRSIS.passcode(try #require(input.callsign)) == vector.expected.passcode)
        case "login":
            let line = APRSIS.loginLine(
                callsign: try #require(input.callsign),
                passcode: try #require(input.passcode),
                software: "kv4p-ht",
                version: "1.0",
                receive: try #require(input.receive),
                latitude: input.latitude,
                longitude: input.longitudeIsNaN == true ? .nan : input.longitude,
                radiusKm: try #require(input.radiusKm)
            )
            #expect(line == vector.expected.line)
        default:
            #expect(APRSIS.Server(try #require(input.server))?.description == vector.expected.normalized)
        }
    }
}
