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

    static let dataFrames = try! VectorFile<Input, Expected>.load("kiss-sender")
        .filter { $0.input.call == "txAx25" && $0.expected.frames != nil }

    @Test("vector file contains DATA frames")
    func vectorsPresent() {
        #expect(!Self.dataFrames.isEmpty)
    }

    @Test("escaped payload matches the Android DATA frame body", arguments: dataFrames)
    func matchesAndroid(vector: VectorFile<Input, Expected>.Vector) throws {
        let frame = [UInt8](hex: try #require(vector.expected.frames?.first))
        // FEND, KISS command, escaped payload, FEND
        let body = Array(frame.dropFirst(2).dropLast())
        #expect(KISS.escape([UInt8](hex: try #require(vector.input.payload))) == body)
    }
}
