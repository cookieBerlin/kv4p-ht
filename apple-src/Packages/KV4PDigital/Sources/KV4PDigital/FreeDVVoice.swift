import KV4PAudio

/// FreeDV 2400B voice on the host (Android `RadioAudioService`): the radio's modem carries Codec2 1300 frames, the app
/// captures and plays 16 kHz audio. One Codec2 instance encodes and decodes, as on Android.
public final class FreeDVVoice {
    public var gain: MicGain = .none

    private let codec: Codec2
    private var frame: [Int16] = []
    /// The first sample of a pair still waiting for its second.
    private var pendingSample: Int16?

    /// `nil` if Codec2 cannot be created.
    public init?() {
        guard let codec = Codec2() else { return nil }
        self.codec = codec
        frame.reserveCapacity(Codec2.samplesPerFrame)
    }

    /// `sendFreeDvAudio`: the mic gain applies, each pair of 16 kHz samples is averaged to one 8 kHz sample, and every
    /// 320 of them make a frame. A partial frame waits for more samples.
    public func encode(_ samples: some Collection<Int16>) -> [[UInt8]] {
        var frames: [[UInt8]] = []
        for sample in gain.apply(to: samples) {
            guard let first = pendingSample else {
                pendingSample = sample
                continue
            }
            pendingSample = nil
            frame.append(Int16((Int(first) + Int(sample)) / 2))  // Java int division truncates toward zero, too
            if frame.count == Codec2.samplesPerFrame, let encoded = codec.encode(frame) {
                frames.append(encoded)
                frame.removeAll(keepingCapacity: true)
            }
        }
        return frames
    }

    /// `decodeAndPlayFreeDvFrame`: 16 kHz audio, every decoded sample twice; `nil` for a frame of another length.
    public func decode(_ frame: some Collection<UInt8>) -> [Int16]? {
        codec.decode(frame)?.flatMap { [$0, $0] }
    }

    /// A new transmission starts (`startPtt`, `setFreeDv2400bEnabled`).
    public func reset() {
        frame.removeAll(keepingCapacity: true)
        pendingSample = nil
    }
}
