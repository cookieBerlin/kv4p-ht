import KV4PTestSupport
import Testing

@testable import KV4PAudio

/// Checks `ImaAdpcm` against the Android `ImaAdpcm` encoder and decoder.
@Suite("IMA ADPCM vectors")
struct ImaAdpcmVectorTests {
    struct Input: Decodable, Sendable {
        let call: String
        let pcm: [Int16]?
        let blockSamples: Int?
        let adpcm: String?
        let samples: Int?
    }

    struct Expected: Decodable, Sendable {
        let encodedSize: Int?
        let adpcm: String?
        let decoded: [Int16]?
        let blocks: [String]?
    }

    typealias Vector = VectorFile<Input, Expected>.Vector

    static let vectors = (try? VectorFile<Input, Expected>.load("ima-adpcm", from: .module)) ?? []

    @Test("vector file covers every call")
    func vectorsPresent() {
        #expect(Set(Self.vectors.map(\.input.call)) == ["encodeBlock", "Encoder.encodeBlock", "decodeBlock"])
    }

    @Test("block round trip matches Android", arguments: vectors.filter { $0.input.call == "encodeBlock" })
    func roundTrip(vector: Vector) throws {
        let pcm = try #require(vector.input.pcm)
        let adpcm = ImaAdpcm.encodeBlock(pcm)
        #expect(ImaAdpcm.encodedSize(samples: pcm.count) == vector.expected.encodedSize)
        #expect(adpcm == (try [UInt8](hex: #require(vector.expected.adpcm))))
        #expect(ImaAdpcm.decodeBlock(adpcm, maxSamples: pcm.count) == vector.expected.decoded)
    }

    @Test("stateful encoder matches Android", arguments: vectors.filter { $0.input.call == "Encoder.encodeBlock" })
    func stream(vector: Vector) throws {
        let pcm = try #require(vector.input.pcm)
        let blockSamples = try #require(vector.input.blockSamples)
        var encoder = ImaAdpcm.Encoder()
        let blocks = stride(from: 0, to: pcm.count, by: blockSamples).map {
            encoder.encodeBlock(pcm[$0..<$0 + blockSamples])
        }
        #expect(try blocks == #require(vector.expected.blocks).map { try [UInt8](hex: $0) })
    }

    @Test("decoder matches Android", arguments: vectors.filter { $0.input.call == "decodeBlock" })
    func decode(vector: Vector) throws {
        let adpcm = try [UInt8](hex: #require(vector.input.adpcm))
        let samples = try #require(vector.input.samples)
        #expect(ImaAdpcm.decodeBlock(adpcm, maxSamples: samples) == vector.expected.decoded)
    }

    @Test("reset encoder starts again at step index 0")
    func encoderReset() {
        let loud: [Int16] = [0, 30000, -30000, 30000]
        var encoder = ImaAdpcm.Encoder()
        _ = encoder.encodeBlock(loud)
        encoder.reset()
        #expect(encoder.encodeBlock(loud) == ImaAdpcm.encodeBlock(loud))
    }

    @Test("encoder ignores an empty block")
    func encoderEmptyBlock() {
        var encoder = ImaAdpcm.Encoder()
        #expect(encoder.encodeBlock([]) == [])
    }
}
