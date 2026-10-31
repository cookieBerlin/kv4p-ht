import KV4PProtocol
import Synchronization

/// Takes the `RX_AUDIO` blocks of the radio.
public protocol RXAudioSink: Sendable {
    func receive(block: [UInt8])
    /// Discards buffered audio, e.g. when the connection ends.
    func reset()
}

/// Decodes `RX_AUDIO` blocks into a jitter buffer and renders them for the audio output (Android
/// `RadioAudioService.handleRxAudio`). `render(into:)` runs on the real-time audio thread; the lock is held only
/// to copy samples.
public final class RXAudioPlayer: RXAudioSink {
    public struct Statistics: Equatable, Sendable {
        public var buffered: Int
        public var underruns: Int
        public var droppedSamples: Int
    }

    private struct State {
        var buffer: JitterBuffer
        var volume: Float = 1
        /// Reused by `render(into:)`, so the audio thread does not allocate.
        var scratch = [Int16](repeating: 0, count: 1024)
    }

    private let state: Mutex<State>

    public init(buffer: JitterBuffer = JitterBuffer()) {
        state = Mutex(State(buffer: buffer))
    }

    /// Output gain, 0…1.
    public var volume: Float {
        get { state.withLock { $0.volume } }
        set { state.withLock { $0.volume = min(max(newValue, 0), 1) } }
    }

    public var statistics: Statistics {
        state.withLock {
            Statistics(
                buffered: $0.buffer.count,
                underruns: $0.buffer.underruns,
                droppedSamples: $0.buffer.droppedSamples
            )
        }
    }

    public func receive(block: [UInt8]) {
        let samples = ImaAdpcm.decodeBlock(block, maxSamples: KV4P.audioBlockSamples)
        state.withLock { $0.buffer.push(samples) }
    }

    public func reset() {
        state.withLock { $0.buffer.reset() }
    }

    /// Fills `output` with samples in -1…1, silence where no audio is buffered.
    public func render(into output: UnsafeMutableBufferPointer<Float>) {
        state.withLock { state in
            if state.scratch.count < output.count {
                state.scratch = [Int16](repeating: 0, count: output.count)
            }
            let gain = state.volume / 32768
            state.scratch.withUnsafeMutableBufferPointer { scratch in
                let samples = UnsafeMutableBufferPointer(rebasing: scratch[..<output.count])
                state.buffer.pull(into: samples)
                for index in output.indices {
                    output[index] = Float(samples[index]) * gain
                }
            }
        }
    }
}
