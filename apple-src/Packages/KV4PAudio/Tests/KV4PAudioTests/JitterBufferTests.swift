import KV4PProtocol
import Testing

@testable import KV4PAudio

extension JitterBuffer {
    mutating func pull(_ count: Int) -> [Int16] {
        [Int16](unsafeUninitializedCapacity: count) { output, initialized in
            pull(into: output)
            initialized = count
        }
    }
}

@Suite("Jitter buffer")
struct JitterBufferTests {
    @Test("defaults to 4 blocks of prefill and 16 blocks of capacity")
    func defaults() {
        let buffer = JitterBuffer()
        #expect(buffer.prefill == 4 * KV4P.audioBlockSamples)
        #expect(buffer.capacity == 16 * KV4P.audioBlockSamples)
    }

    @Test("plays silence until the prefill is buffered")
    func prefill() {
        var buffer = JitterBuffer(prefill: 3, capacity: 8)
        buffer.push([1, 2])
        #expect(buffer.pull(2) == [0, 0])
        #expect(!buffer.isPlaying)
        buffer.push([3])
        #expect(buffer.pull(2) == [1, 2])
        #expect(buffer.isPlaying)
        #expect(buffer.count == 1)
    }

    @Test("an underrun fills with silence and buffers the prefill again")
    func underrun() {
        var buffer = JitterBuffer(prefill: 2, capacity: 8)
        buffer.push([1, 2, 3])
        #expect(buffer.pull(2) == [1, 2])
        #expect(buffer.pull(3) == [3, 0, 0])
        #expect(buffer.underruns == 1)
        #expect(!buffer.isPlaying)
        buffer.push([4])
        #expect(buffer.pull(1) == [0])
        #expect(buffer.underruns == 1)
    }

    @Test("draining the buffer exactly is no underrun")
    func exactDrain() {
        var buffer = JitterBuffer(prefill: 2, capacity: 8)
        buffer.push([1, 2])
        #expect(buffer.pull(2) == [1, 2])
        #expect(buffer.underruns == 0)
        #expect(buffer.isPlaying)
    }

    @Test("an overflow drops the oldest samples to bound the latency")
    func overflow() {
        var buffer = JitterBuffer(prefill: 1, capacity: 4)
        buffer.push([1, 2, 3])
        buffer.push([4, 5, 6])
        #expect(buffer.droppedSamples == 2)
        #expect(buffer.pull(4) == [3, 4, 5, 6])
    }

    @Test("a push larger than the capacity keeps the newest samples")
    func oversizedPush() {
        var buffer = JitterBuffer(prefill: 1, capacity: 2)
        buffer.push([1, 2, 3])
        #expect(buffer.droppedSamples == 1)
        #expect(buffer.pull(2) == [2, 3])
    }

    @Test("samples keep their order across the end of the ring")
    func wraparound() {
        var buffer = JitterBuffer(prefill: 1, capacity: 4)
        buffer.push([1, 2, 3])
        #expect(buffer.pull(2) == [1, 2])
        buffer.push([4, 5, 6])
        #expect(buffer.pull(4) == [3, 4, 5, 6])
    }

    @Test("the prefill never exceeds the capacity")
    func prefillClamped() {
        let buffer = JitterBuffer(prefill: 10, capacity: 4)
        #expect(buffer.prefill == 4)
    }

    @Test("reset empties the buffer and its statistics")
    func reset() {
        var buffer = JitterBuffer(prefill: 1, capacity: 2)
        buffer.push([1, 2, 3])
        _ = buffer.pull(4)
        buffer.reset()
        #expect(buffer.count == 0)
        #expect(!buffer.isPlaying)
        #expect(buffer.underruns == 0)
        #expect(buffer.droppedSamples == 0)
        buffer.push([7])
        #expect(buffer.pull(1) == [7])
    }
}
