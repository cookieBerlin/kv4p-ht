import KV4PProtocol

/// Microphone gain boost (Android `MicGainBoost`).
public enum MicGain: String, CaseIterable, Codable, Sendable {
    case none, low, med, high

    public var factor: Float {
        switch self {
        case .none: 1.0
        case .low: 1.5
        case .med: 2.0
        case .high: 2.5
        }
    }

    public var label: String {
        switch self {
        case .none: "None"
        case .low: "Low"
        case .med: "Med"
        case .high: "High"
        }
    }

    /// `RadioAudioService.applyMicGain`: rounded half up like `Math.round`, clamped to 16 bits.
    public func apply(to samples: some Collection<Int16>) -> [Int16] {
        guard self != .none else { return Array(samples) }
        return samples.map { sample in
            let scaled = (Float(sample) * factor + 0.5).rounded(.down)
            return Int16(min(max(scaled, Float(Int16.min)), Float(Int16.max)))
        }
    }
}

/// Turns captured 16 kHz samples into `HOST_TX_AUDIO` blocks (Android `sendAudioToESP32`): 249 samples per block,
/// mic gain applied, encoded as one continuous IMA ADPCM stream.
public struct TXAudioEncoder: Sendable {
    public var gain: MicGain
    private var encoder = ImaAdpcm.Encoder()
    private var pending: [Int16] = []

    public init(gain: MicGain = .none) {
        self.gain = gain
    }

    /// The blocks completed by `samples`; a partial block waits for more samples.
    public mutating func encode(_ samples: some Collection<Int16>) -> [[UInt8]] {
        pending.append(contentsOf: samples)
        var blocks: [[UInt8]] = []
        while pending.count >= KV4P.audioBlockSamples {
            let block = pending.prefix(KV4P.audioBlockSamples)
            pending.removeFirst(KV4P.audioBlockSamples)
            blocks.append(encoder.encodeBlock(gain.apply(to: block)))
        }
        return blocks
    }

    /// A new transmission starts.
    public mutating func reset() {
        encoder.reset()
        pending = []
    }
}
