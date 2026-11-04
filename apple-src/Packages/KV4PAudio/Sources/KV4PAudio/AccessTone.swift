import Foundation
import KV4PProtocol

/// The tone that opens a repeater, and the silence that gives the radio time to open up first (ADR-0045).
public struct AccessTone: Equatable, Sendable {
    public static let frequencies = [1000, 1450, 1750, 2100]
    public static let lengthsMs = [250, 500, 1000, 2000, 3000, 4000, 5000]
    public static let waitsMs = [0, 100, 200, 300, 500, 1000]
    public static let defaultLengthMs = 1000
    public static let defaultWaitMs = 200

    /// Half of full scale, for now: the deviation it causes is for a hardware test to check.
    private static let level = 0.5
    /// Keeps the edges from clicking, which would splatter on air.
    private static let rampSeconds = 0.005

    public var frequency: Int
    public var lengthMs: Int
    public var waitMs: Int

    public init(frequency: Int, lengthMs: Int, waitMs: Int) {
        self.frequency = frequency
        self.lengthMs = lengthMs
        self.waitMs = waitMs
    }

    public var waitSamples: Int { waitMs * KV4P.audioSampleRate / 1000 }

    /// The tone at the rate of the radio.
    public func samples() -> [Int16] {
        let rate = Double(KV4P.audioSampleRate)
        let count = lengthMs * KV4P.audioSampleRate / 1000
        let ramp = rate * Self.rampSeconds
        return (0..<count).map { index in
            let edge = min(Double(index), Double(count - 1 - index))
            let envelope = min(edge / ramp, 1)
            let wave = sin(2 * .pi * Double(frequency) * Double(index) / rate)
            return Int16(wave * envelope * Self.level * Double(Int16.max))
        }
    }
}
