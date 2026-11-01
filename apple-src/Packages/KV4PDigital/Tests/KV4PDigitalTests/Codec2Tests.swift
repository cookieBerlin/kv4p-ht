import CCodec2
import KV4PTestSupport
import Testing

@testable import KV4PDigital

/// Checks the Codec2 wrapper against the pinned upstream build (tools/codec2-vectors).
@Suite("Codec2 vectors")
struct Codec2Tests {
    struct Input: Decodable, Sendable {
        let pcm: [Int16]
    }

    struct Expected: Decodable, Sendable {
        let frames: [String]
        let pcm: [Int16]
    }

    static let vectors = (try? VectorFile<Input, Expected>.load("codec2", from: .module)) ?? []

    /// SwiftPM debug builds compile the C code without optimisation, which changes a decoded sample by at most one.
    static func expectClose(_ decoded: [Int16], _ expected: [Int16]) {
        #expect(decoded.count == expected.count)
        let differences = zip(decoded, expected).map { abs(Int($0) - Int($1)) }
        #expect(differences.allSatisfy { $0 <= 1 })
    }

    @Test("vector file is present")
    func vectorsPresent() {
        #expect(Self.vectors.map(\.name) == ["silence", "voiced", "noise"])
    }

    @Test("encodes 320 samples into the frames upstream encodes, and decodes them", arguments: vectors)
    func codec(vector: VectorFile<Input, Expected>.Vector) throws {
        let encoder = try #require(Codec2())
        let decoder = try #require(Codec2())
        var frames: [[UInt8]] = []
        var decoded: [Int16] = []
        for start in stride(from: 0, to: vector.input.pcm.count, by: Codec2.samplesPerFrame) {
            let frame = try #require(encoder.encode(vector.input.pcm[start..<start + Codec2.samplesPerFrame]))
            frames.append(frame)
            decoded += try #require(decoder.decode(frame))
        }
        #expect(frames == (try vector.expected.frames.map { try [UInt8](hex: $0) }))
        Self.expectClose(decoded, vector.expected.pcm)
    }

    @Test("frames and sample blocks of another length are refused")
    func lengths() throws {
        let codec = try #require(Codec2())
        #expect(codec.encode([Int16](repeating: 0, count: 319)) == nil)
        #expect(codec.decode([UInt8](repeating: 0, count: 8)) == nil)
        #expect(Codec2.samplesPerFrame == 320)
        #expect(Codec2.bytesPerFrame == 7)
    }

    @Test("modes that are not compiled in are unavailable")
    func unavailableMode() {
        #expect(Codec2(mode: CODEC2_MODE_3200) == nil)
    }
}
