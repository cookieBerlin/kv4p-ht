import KV4PTestSupport
import Testing

@testable import KV4PAPRS

/// Checks message payloads and AX.25 frames against java-aprs.
@Suite("APRS encoding vectors")
struct APRSEncodingVectorTests {
    struct Input: Decodable, Sendable {
        let kind: String
        let to: String?
        let text: String?
        let id: String?
        let source: String?
        let destination: String?
        let path: String?
        let payload: String?
    }

    struct Expected: Decodable, Sendable {
        let bytes: String?
        let error: Bool?
    }

    static let vectors = (try? VectorFile<Input, Expected>.load("aprs-encoding", from: .module)) ?? []

    @Test("vector file is present")
    func vectorsPresent() {
        #expect(Self.vectors.count == 14)
    }

    @Test("encodes like Android", arguments: vectors)
    func encodes(vector: VectorFile<Input, Expected>.Vector) throws {
        let input = vector.input
        if input.kind == "payload" {
            let payload = MessageField.payload(
                to: try #require(input.to),
                text: try #require(input.text),
                identifier: input.id
            )
            #expect(payload == (try [UInt8](hex: try #require(vector.expected.bytes))))
            return
        }
        let path = try #require(input.path)
        let packet = APRSPacket(
            source: try #require(input.source),
            destination: try #require(input.destination),
            digipeaters: path.isEmpty ? [] : Java.split(path, ",").compactMap(AX25Address.init),
            payload: Java.latin1Bytes(try #require(input.payload))
        )
        if vector.expected.error == true {
            #expect(throws: APRSEncodeError.callsignTooLong) { try packet.ax25Frame() }
        } else {
            #expect(try packet.ax25Frame() == (try [UInt8](hex: try #require(vector.expected.bytes))))
        }
    }
}
