/// IMA ADPCM, mono WAV block layout (`docs/apple/03-protocol-spec.md` §5). Port of the Android `ImaAdpcm`.
///
/// A block is a 4-byte header (first sample, step index, reserved) followed by one 4-bit delta per further
/// sample, low nibble first.
public enum ImaAdpcm {
    private static let indexTable = [-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8]

    private static let stepTable: [Int] = [
        7, 8, 9, 10, 11, 12, 13, 14, 16, 17,
        19, 21, 23, 25, 28, 31, 34, 37, 41, 45,
        50, 55, 60, 66, 73, 80, 88, 97, 107, 118,
        130, 143, 157, 173, 190, 209, 230, 253, 279, 307,
        337, 371, 408, 449, 494, 544, 598, 658, 724, 796,
        876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066,
        2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358,
        5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899,
        15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767,
    ]

    private static let headerSize = 4

    /// Predictor and step index between two samples.
    private struct State {
        var predictor: Int
        var index: Int
    }

    /// Encodes a continuous stream: each block starts with the step index the previous one ended with.
    public struct Encoder: Sendable {
        private var stepIndex = 0

        public init() {}

        public mutating func encodeBlock(_ pcm: some Collection<Int16>) -> [UInt8] {
            guard let first = pcm.first else { return [] }
            var state = State(predictor: Int(first), index: stepIndex)
            let block = ImaAdpcm.encodeBlock(pcm, state: &state)
            stepIndex = state.index
            return block
        }

        public mutating func reset() {
            stepIndex = 0
        }
    }

    public static func encodedSize(samples: Int) -> Int {
        headerSize + samples / 2
    }

    /// Encodes one block starting at step index 0.
    public static func encodeBlock(_ pcm: some Collection<Int16>) -> [UInt8] {
        var state = State(predictor: Int(pcm.first ?? 0), index: 0)
        return encodeBlock(pcm, state: &state)
    }

    /// Decodes at most `maxSamples` samples; a block shorter than its header decodes to nothing.
    public static func decodeBlock(_ adpcm: some Collection<UInt8>, maxSamples: Int) -> [Int16] {
        let bytes = Array(adpcm)
        guard bytes.count >= headerSize, maxSamples > 0 else { return [] }
        var state = State(
            predictor: Int(Int16(bitPattern: UInt16(bytes[0]) | UInt16(bytes[1]) << 8)),
            index: clampIndex(Int(bytes[2]))
        )
        var pcm = [Int16(state.predictor)]
        pcm.reserveCapacity(min(maxSamples, 1 + 2 * (bytes.count - headerSize)))
        for packed in bytes.dropFirst(headerSize) {
            for code in [packed & 0x0F, packed >> 4] where pcm.count < maxSamples {
                decodeNibble(Int(code), state: &state)
                pcm.append(Int16(state.predictor))
            }
        }
        return pcm
    }

    private static func encodeBlock(_ pcm: some Collection<Int16>, state: inout State) -> [UInt8] {
        guard let first = pcm.first else { return [] }
        let predictor = UInt16(bitPattern: first)
        var block = [UInt8(truncatingIfNeeded: predictor), UInt8(predictor >> 8), UInt8(state.index), 0]
        block.reserveCapacity(encodedSize(samples: pcm.count))
        var low: UInt8?
        for sample in pcm.dropFirst() {
            let code = encodeNibble(sample, state: &state)
            if let packed = low {
                block.append(packed | code << 4)
                low = nil
            } else {
                low = code
            }
        }
        if let low {
            block.append(low)
        }
        return block
    }

    private static func encodeNibble(_ sample: Int16, state: inout State) -> UInt8 {
        let step = stepTable[state.index]
        let diff = Int(sample) - state.predictor
        let magnitude = min(7, abs(diff) * 4 / step)
        let code = magnitude | (diff < 0 ? 8 : 0)
        let delta = step * (2 * magnitude + 1) / 8
        state.predictor = clampInt16(state.predictor + (diff < 0 ? -delta : delta))
        state.index = clampIndex(state.index + indexTable[code])
        return UInt8(code)
    }

    private static func decodeNibble(_ code: Int, state: inout State) {
        let step = stepTable[state.index]
        var delta = step >> 3
        if code & 4 != 0 { delta += step }
        if code & 2 != 0 { delta += step >> 1 }
        if code & 1 != 0 { delta += step >> 2 }
        state.predictor = clampInt16(state.predictor + (code & 8 != 0 ? -delta : delta))
        state.index = clampIndex(state.index + indexTable[code])
    }

    private static func clampInt16(_ sample: Int) -> Int {
        min(max(sample, Int(Int16.min)), Int(Int16.max))
    }

    private static func clampIndex(_ index: Int) -> Int {
        min(max(index, 0), stepTable.count - 1)
    }
}
