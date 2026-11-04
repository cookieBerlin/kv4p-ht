import KV4PProtocol

/// Buffers received audio so that irregular block arrival (BLE connection intervals, USB bursts) plays at the
/// steady rate of the output device.
///
/// Playback starts once `prefill` samples are buffered. An underrun plays silence and buffers the prefill
/// again; an overflow drops the oldest samples, so the latency never exceeds `capacity`.
public struct JitterBuffer: Sendable {
    /// Samples buffered before playback starts or resumes.
    public let prefill: Int
    public let capacity: Int
    /// The limit while `isHolding`, as long as the longest switch of the audio session takes (ADR-0043).
    public let holdCapacity: Int
    /// Keeps audio that cannot play yet instead of dropping it above `capacity`.
    public var isHolding = false
    public private(set) var count = 0
    public private(set) var isPlaying = false
    public private(set) var underruns = 0
    public private(set) var droppedSamples = 0

    private var ring: [Int16]
    private var head = 0

    public init(
        prefill: Int = 4 * KV4P.audioBlockSamples,
        capacity: Int = 16 * KV4P.audioBlockSamples,
        holdCapacity: Int = 128 * KV4P.audioBlockSamples
    ) {
        self.prefill = min(prefill, capacity)
        self.capacity = capacity
        self.holdCapacity = max(capacity, holdCapacity)
        ring = Array(repeating: 0, count: self.holdCapacity)
    }

    public mutating func push(_ samples: some Collection<Int16>) {
        let limit = isHolding ? holdCapacity : capacity
        let kept = samples.suffix(limit)
        droppedSamples += samples.count - kept.count
        let overflow = max(0, count + kept.count - limit)
        droppedSamples += overflow
        head = (head + overflow) % ring.count
        count -= overflow
        for sample in kept {
            ring[(head + count) % ring.count] = sample
            count += 1
        }
    }

    /// Fills `output` completely, with silence where no audio is available.
    public mutating func pull(into output: UnsafeMutableBufferPointer<Int16>) {
        if !isPlaying, count >= prefill {
            isPlaying = true
        }
        let available = isPlaying ? min(count, output.count) : 0
        for index in 0..<available {
            output[index] = ring[(head + index) % ring.count]
        }
        head = (head + available) % ring.count
        count -= available
        if available < output.count {
            UnsafeMutableBufferPointer(rebasing: output[available...]).update(repeating: 0)
            if isPlaying {
                underruns += 1
                isPlaying = false
            }
        }
    }

    public mutating func reset() {
        self = JitterBuffer(prefill: prefill, capacity: capacity, holdCapacity: holdCapacity)
    }

    /// Drops what is buffered, e.g. the silence of a closed squelch; the statistics stay.
    public mutating func discard() {
        count = 0
        isPlaying = false
    }
}
