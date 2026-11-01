import KV4PAudio
import KV4PSimulator
import KV4PTestSupport
import Testing

@testable import KV4PDigital

/// Android `RadioAudioService.sendFreeDvAudio` and `decodeAndPlayFreeDvFrame`.
@Suite("FreeDV voice")
struct FreeDVVoiceTests {
    /// Every 8 kHz sample twice, as 16 kHz audio.
    static func doubled(_ samples: [Int16]) -> [Int16] {
        samples.flatMap { [$0, $0] }
    }

    @Test("16 kHz audio of a vector encodes into its frames; frames decode to doubled samples")
    func vector() throws {
        let vector = try #require(Codec2Tests.vectors.first { $0.name == "voiced" })
        let tx = try #require(FreeDVVoice())
        let rx = try #require(FreeDVVoice())
        let frames = tx.encode(Self.doubled(vector.input.pcm))
        #expect(frames == (try vector.expected.frames.map { try [UInt8](hex: $0) }))
        var decoded: [Int16] = []
        for frame in frames {
            let samples = try #require(rx.decode(frame))
            #expect(samples.count == 2 * Codec2.samplesPerFrame)
            #expect(stride(from: 0, to: samples.count, by: 2).allSatisfy { samples[$0] == samples[$0 + 1] })
            decoded += stride(from: 0, to: samples.count, by: 2).map { samples[$0] }
        }
        Codec2Tests.expectLevels(decoded, vector.expected.rms)
    }

    @Test("pairs are averaged like Java ints, across chunks; a partial frame waits")
    func downsampling() throws {
        let voice = try #require(FreeDVVoice())
        let reference = try #require(Codec2())
        let input = (0..<640).map { Int16(truncatingIfNeeded: $0 * 97 % 2001 - 1000) }
        #expect(voice.encode(input[..<1]).isEmpty)
        #expect(voice.encode(input[1..<639]).isEmpty)
        let frames = voice.encode(input[639...])
        let averaged = stride(from: 0, to: 640, by: 2).map { Int16((Int(input[$0]) + Int(input[$0 + 1])) / 2) }
        #expect(frames == [try #require(reference.encode(averaged))])
        #expect((Int(-3) + Int(0)) / 2 == -1)  // truncation toward zero, as `(short) ((a + b) / 2)` in Java
    }

    @Test("the mic gain applies before averaging; reset drops the pending samples")
    func gainAndReset() throws {
        let voice = try #require(FreeDVVoice())
        let reference = try #require(Codec2())
        voice.gain = .high
        #expect(voice.gain == .high)
        _ = voice.encode([Int16](repeating: 500, count: 3))
        voice.reset()
        let input = [Int16](repeating: 1001, count: 640)
        let frames = voice.encode(input)
        let expected = MicGain.high.apply(to: [1001, 1001])
        let sample = Int16((Int(expected[0]) + Int(expected[1])) / 2)
        #expect(frames == [try #require(reference.encode([Int16](repeating: sample, count: 320)))])
    }

    @Test("the simulator's FreeDV signal carries the frames of the voiced vector")
    func simulatorSignal() throws {
        let vector = try #require(Codec2Tests.vectors.first { $0.name == "voiced" })
        #expect(Carrier.freeDVVoice.voiceFrames == (try vector.expected.frames.map { try [UInt8](hex: $0) }))
    }

    @Test("frames of another length are not decoded")
    func invalidFrame() throws {
        let voice = try #require(FreeDVVoice())
        #expect(voice.decode([1, 2, 3]) == nil)
    }
}
