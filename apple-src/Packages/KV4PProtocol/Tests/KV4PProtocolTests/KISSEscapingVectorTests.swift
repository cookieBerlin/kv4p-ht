import KV4PTestSupport
import Testing

@testable import KV4PProtocol

/// Checks `KISS.escape` against KISS DATA frames produced by the Android `Protocol.Sender`.
@Suite("KISS escaping vectors")
struct KISSEscapingVectorTests {
    struct Input: Decodable, Sendable {
        let call: String
        let payload: String?
    }

    struct Expected: Decodable, Sendable {
        let frames: [String]?
    }

    // A load failure leaves this empty, which `vectorsPresent` reports.
    static let dataFrames = ((try? VectorFile<Input, Expected>.load("kiss-sender", from: .module)) ?? [])
        .filter { $0.input.call == "txAx25" && $0.expected.frames != nil }

    @Test("vector file contains DATA frames")
    func vectorsPresent() {
        #expect(!Self.dataFrames.isEmpty)
    }

    @Test("escaped payload matches the Android DATA frame body", arguments: dataFrames)
    func matchesAndroid(vector: VectorFile<Input, Expected>.Vector) throws {
        let frame = try [UInt8](hex: try #require(vector.expected.frames?.first))
        // FEND, KISS command, escaped payload, FEND
        let body = Array(frame.dropFirst(2).dropLast())
        #expect(KISS.escape(try [UInt8](hex: try #require(vector.input.payload))) == body)
    }
}
