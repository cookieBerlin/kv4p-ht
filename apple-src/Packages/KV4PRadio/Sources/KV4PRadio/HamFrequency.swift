import Foundation
import KV4PPersistence

/// Frequencies as the Android app normalises them (`RadioAudioService.makeSafeHamFreq`).
public enum HamFrequency {
    /// An entered frequency in MHz: `1467` → `146.7`, clamped to `range`, four decimals; `nil` if not a number.
    public static func safe(_ text: String, in range: ClosedRange<Float>) -> Float? {
        guard var frequency = Float(text.trimmingCharacters(in: .whitespaces)), frequency.isFinite else { return nil }
        while frequency > 500 {
            frequency /= 10
        }
        return safe(frequency, in: range)
    }

    /// Clamped to `range` and rounded to four decimals, as the formatted string Android parses again.
    public static func safe(_ frequency: Float, in range: ClosedRange<Float>) -> Float {
        let clamped = min(max(frequency, range.lowerBound), range.upperBound)
        return Float((Double(clamped) * 10_000).rounded() / 10_000)
    }

    /// Four decimals, as in the Android app.
    public static func format(_ frequency: Float) -> String {
        String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), Double(frequency))
    }
}

extension ChannelMemory {
    /// `RadioAudioService.getTxFreq`: the RX frequency shifted by the offset, made safe.
    public func txFrequency(in range: ClosedRange<Float>) -> Float {
        let shift = Float(offsetKHz) / 1000
        switch offset {
        case .none: return HamFrequency.safe(frequency, in: range)
        case .down: return HamFrequency.safe(frequency - shift, in: range)
        case .up: return HamFrequency.safe(frequency + shift, in: range)
        }
    }
}
