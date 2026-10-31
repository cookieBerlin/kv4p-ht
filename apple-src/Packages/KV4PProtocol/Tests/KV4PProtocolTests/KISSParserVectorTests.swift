import Testing

@testable import KV4PProtocol

/// Checks `KISSParser` against the events of the Android `Protocol.KissParser`.
@Suite("KISS parser vectors")
struct KISSParserVectorTests {
    struct Input: Decodable, Sendable {
        let stream: String
    }

    struct Event: Decodable, Sendable {
        let type: String
        let command: UInt8?
        let payload: String

        func frame() throws -> ReceivedFrame {
            let bytes = try [UInt8](hex: payload)
            guard type == "command" else { return .ax25(bytes) }
            let raw = try #require(command)
            return .command(try #require(DeviceCommand(rawValue: raw)), payload: bytes)
        }
    }

    struct Expected: Decodable, Sendable {
        let events: [Event]
    }

    typealias Vector = VectorFile<Input, Expected>.Vector

    static let vectors = (try? VectorFile<Input, Expected>.load("kiss-parser")) ?? []

    @Test("vector file is present")
    func vectorsPresent() {
        #expect(!Self.vectors.isEmpty)
    }

    @Test("whole stream yields the Android events", arguments: vectors)
    func wholeStream(vector: Vector) throws {
        var parser = KISSParser()
        let frames = parser.process(try [UInt8](hex: vector.input.stream))
        #expect(frames == (try vector.expected.events.map { try $0.frame() }))
    }

    @Test("byte-by-byte stream yields the same events", arguments: vectors)
    func byteByByte(vector: Vector) throws {
        var parser = KISSParser()
        let frames = try [UInt8](hex: vector.input.stream).flatMap { parser.process([$0]) }
        #expect(frames == (try vector.expected.events.map { try $0.frame() }))
    }
}
