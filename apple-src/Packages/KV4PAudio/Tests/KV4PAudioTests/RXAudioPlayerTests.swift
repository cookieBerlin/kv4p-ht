import KV4PProtocol
import Testing

@testable import KV4PAudio

extension RXAudioPlayer {
    func render(_ count: Int) -> [Float] {
        [Float](unsafeUninitializedCapacity: count) { output, initialized in
            render(into: output)
            initialized = count
        }
    }
}

@Suite("RX audio player")
struct RXAudioPlayerTests {
    static let samples: [Int16] = [0, 16384, -16384, 32767, -32768]
    static let block = ImaAdpcm.encodeBlock(samples)
    static var decoded: [Float] {
        ImaAdpcm.decodeBlock(block, maxSamples: samples.count).map { Float($0) / 32768 }
    }

    @Test("plays decoded blocks once the jitter buffer is filled")
    func playsDecodedBlocks() {
        let player = RXAudioPlayer(buffer: JitterBuffer(prefill: Self.samples.count, capacity: 16), fadesIn: false)
        #expect(player.render(2) == [0, 0])
        player.receive(block: Self.block)
        #expect(player.render(Self.samples.count) == Self.decoded)
    }

    @Test("scales the samples by the volume")
    func volume() {
        let player = RXAudioPlayer(buffer: JitterBuffer(prefill: 1, capacity: 16), fadesIn: false)
        #expect(player.volume == 1)
        player.volume = 0.5
        player.receive(block: Self.block)
        #expect(player.render(Self.samples.count) == Self.decoded.map { $0 * 0.5 })
    }

    @Test("clamps the volume to 0…1")
    func volumeClamped() {
        let player = RXAudioPlayer()
        player.volume = 2
        #expect(player.volume == 1)
        player.volume = -1
        #expect(player.volume == 0)
    }

    @Test("decodes at most one block of samples, as Android does")
    func blockLimit() {
        let player = RXAudioPlayer(buffer: JitterBuffer(prefill: 1, capacity: 1024))
        player.receive(block: ImaAdpcm.encodeBlock([Int16](repeating: 0, count: 2 * KV4P.audioBlockSamples)))
        _ = player.render(1)
        #expect(player.statistics.buffered == KV4P.audioBlockSamples - 1)
    }

    @Test("reports underruns and dropped samples")
    func statistics() {
        let player = RXAudioPlayer(buffer: JitterBuffer(prefill: 1, capacity: 4))
        player.receive(block: Self.block)
        _ = player.render(8)
        #expect(player.statistics == RXAudioPlayer.Statistics(buffered: 0, underruns: 1, droppedSamples: 1))
    }

    @Test("reset discards the buffered audio")
    func reset() {
        let player = RXAudioPlayer(buffer: JitterBuffer(prefill: 1, capacity: 16), fadesIn: false)
        player.receive(block: Self.block)
        player.reset()
        #expect(player.statistics.buffered == 0)
        #expect(player.render(1) == [0])
    }

    @Test("renders more frames than one block in one call")
    func largeRender() {
        let player = RXAudioPlayer(buffer: JitterBuffer(prefill: 1, capacity: 16), fadesIn: false)
        player.receive(block: Self.block)
        let output = player.render(4096)
        #expect(Array(output.prefix(Self.samples.count)) == Self.decoded)
        #expect(output.dropFirst(Self.samples.count).allSatisfy { $0 == 0 })
    }

    /// `RadioAudioService.ensureAudioPlaying`: muted until the volume ramp passes 0.7, which hides the
    /// transient the radio sends after it starts.
    @Test("fades in like Android: muted for 59 blocks, then 70 % rising to full volume")
    func fadeIn() {
        let player = RXAudioPlayer(buffer: JitterBuffer(prefill: 1, capacity: 4096))
        let block = ImaAdpcm.encodeBlock([Int16](repeating: 16384, count: 3))
        let alpha: Float = 0.02
        var ramp: Float = 0
        for count in 1...61 {
            player.receive(block: block)
            ramp = alpha + (1 - alpha) * ramp
            let output = player.render(3)
            let expected: Float = ramp > 0.7 ? ramp * 16384 / 32768 : 0
            #expect(output.first == expected, "block \(count)")
            #expect((count < 60) == (output.first == 0), "block \(count)")
        }
        player.reset()
        player.receive(block: block)
        #expect(player.render(1) == [0])
    }
}
