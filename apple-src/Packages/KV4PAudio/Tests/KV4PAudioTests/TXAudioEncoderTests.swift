import KV4PProtocol
import Testing

@testable import KV4PAudio

/// Microphone gain and block encoding as in the Android `RadioAudioService.sendAudioToESP32`.
@Suite("TX audio encoder")
struct TXAudioEncoderTests {
    @Test("gain levels of MicGainBoost")
    func levels() {
        #expect(MicGain.allCases.map(\.factor) == [1.0, 1.5, 2.0, 2.5])
        #expect(MicGain.allCases.map(\.label) == ["None", "Low", "Med", "High"])
    }

    /// `applyMicGain`: `Math.round` (half up), then clamped to 16 bits.
    @Test("gain rounds half up like Java and clamps")
    func apply() {
        let samples: [Int16] = [1, -1, 3, -3, 20000, -20000, 0]
        #expect(MicGain.low.apply(to: samples) == [2, -1, 5, -4, 30000, -30000, 0])
        #expect(MicGain.high.apply(to: samples) == [3, -2, 8, -7, 32767, -32768, 0])
        #expect(MicGain.none.apply(to: samples) == samples)
    }

    @Test("collects 249 samples per block and encodes them as one stream")
    func blocks() {
        let samples = (0..<600).map { Int16(truncatingIfNeeded: $0 * 97) }
        var encoder = TXAudioEncoder()
        let blocks = encoder.encode(samples[..<100]) + encoder.encode(samples[100...])
        var reference = ImaAdpcm.Encoder()
        let expected = [
            reference.encodeBlock(samples[0..<249]),
            reference.encodeBlock(samples[249..<498]),
        ]
        #expect(blocks == expected)
        #expect(blocks.allSatisfy { $0.count == ImaAdpcm.encodedSize(samples: KV4P.audioBlockSamples) })
    }

    @Test("applies the gain before encoding")
    func gain() {
        let samples = [Int16](repeating: 1000, count: KV4P.audioBlockSamples)
        var encoder = TXAudioEncoder(gain: .med)
        #expect(encoder.encode(samples) == [ImaAdpcm.encodeBlock([Int16](repeating: 2000, count: 249))])
    }

    @Test("reset discards the partial block and starts a new stream")
    func reset() {
        let samples = [Int16](repeating: 5000, count: KV4P.audioBlockSamples)
        var encoder = TXAudioEncoder()
        _ = encoder.encode(samples + samples[..<10])
        encoder.reset()
        #expect(encoder.encode(samples) == [ImaAdpcm.encodeBlock(samples)])
    }
}
