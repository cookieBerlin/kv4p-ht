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
        /// The RMS of each decoded frame.
        let rms: [Double]
    }

    static let vectors = (try? VectorFile<Input, Expected>.load("codec2", from: .module)) ?? []

    /// Unvoiced sounds decode with random phases from a process-wide generator, so only the level of each frame is
    /// reproducible: within 30 % or 20 (-64 dBFS) of the upstream build, wider than the spread of 500 generator states.
    static func expectLevels(_ decoded: [Int16], _ rms: [Double]) {
        #expect(decoded.count == rms.count * Codec2.samplesPerFrame)
        for (index, expected) in rms.enumerated() {
            let frame = decoded.dropFirst(index * Codec2.samplesPerFrame).prefix(Codec2.samplesPerFrame)
            let energy = frame.map { Double($0) * Double($0) }.reduce(0, +)
            let level = (energy / Double(Codec2.samplesPerFrame)).squareRoot()
            #expect(abs(level - expected) <= max(0.3 * expected, 20), "frame \(index): RMS \(level), \(expected)")
        }
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
        Self.expectLevels(decoded, vector.expected.rms)
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
