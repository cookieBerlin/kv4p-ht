/// Steps the frequency digit by digit, in the channel raster (ADR-0064).
public enum FrequencyStep {
    /// The digits of the shown frequency, as their value in Hz: 100 MHz to 100 Hz, the fourth decimal.
    public static let digits = [100_000_000, 10_000_000, 1_000_000, 100_000, 10_000, 1_000, 100]
    /// A `Float` in MHz is only close to a frequency; 50 Hz keeps half of 12.5 kHz.
    private static let resolution = 50

    /// The channel raster in Hz: 12.5 kHz with a narrow and 25 kHz with a wide bandwidth.
    public static func raster(isWide: Bool) -> Int { isWide ? 25_000 : 12_500 }

    /// `frequency` stepped `count` times at `digit`, within `range`. A digit at or above the raster steps by its value
    /// and snaps to the nearest multiple of the raster, a lower one steps from multiple to multiple of the raster;
    /// `exact` steps by the digit and does not snap.
    public static func stepped(
        _ frequency: Float,
        digit: Int,
        by count: Int,
        raster: Int,
        exact: Bool,
        in range: ClosedRange<Float>
    ) -> Float {
        let hertz = Int((Double(frequency) * 1_000_000 / Double(resolution)).rounded()) * resolution
        let stepped: Int
        if exact {
            stepped = hertz + digit * count
        } else if digit < raster {
            stepped = rasterStepped(hertz, by: count, raster: raster)
        } else {
            stepped = snapped(hertz + digit * count, to: raster, towards: count)
        }
        return HamFrequency.safe(Float(Double(stepped) / 1_000_000), in: range)
    }

    /// `count` multiples of `raster` on; off the raster, the first one is the next multiple in that direction.
    private static func rasterStepped(_ hertz: Int, by count: Int, raster: Int) -> Int {
        let below = hertz - ((hertz % raster) + raster) % raster
        let start = count < 0 && below != hertz ? below + raster : below
        return start + count * raster
    }

    /// The nearest multiple of `raster`; halfway, the one in the direction of the step.
    private static func snapped(_ hertz: Int, to raster: Int, towards direction: Int) -> Int {
        let below = hertz - ((hertz % raster) + raster) % raster
        let above = below + raster
        let toBelow = hertz - below
        let toAbove = above - hertz
        if toBelow == toAbove { return direction > 0 ? above : below }
        return toBelow < toAbove ? below : above
    }

    /// The digit shown at `index` of `text`, a frequency in MHz with a decimal separator; `nil` for the separator.
    public static func digit(atCharacter index: Int, in text: String) -> Int? {
        let characters = Array(text)
        guard characters.indices.contains(index), characters[index].isNumber,
            let separator = characters.firstIndex(where: { !$0.isNumber })
        else { return nil }
        let exponent = index < separator ? 6 + separator - 1 - index : 6 - (index - separator)
        return digits.first { $0 == (0..<max(exponent, 0)).reduce(1) { value, _ in value * 10 } }
    }

    /// The digit at a cursor at `offset`: the one before it, or the one after it at the start and after the separator.
    public static func digit(atCursor offset: Int, in text: String) -> Int? {
        digit(atCharacter: offset - 1, in: text) ?? digit(atCharacter: offset, in: text)
    }
}

/// What a field for numbers takes.
public enum NumberInput {
    /// Digits, if allowed the first separator, a comma or a point, and if allowed a minus at the start.
    public static func filtered(_ text: String, allowsSeparator: Bool, allowsSign: Bool = false) -> String {
        var hasSeparator = !allowsSeparator
        var result = ""
        for character in text {
            if character.isASCII, character.isNumber {
                result.append(character)
            } else if character == "-", allowsSign, result.isEmpty {
                result.append(character)
            } else if character == "." || character == ",", !hasSeparator {
                hasSeparator = true
                result.append(character)
            }
        }
        return result
    }
}

/// Turns scrolling into steps: a scroll wheel steps once per notch, a trackpad once per `threshold` points.
public struct ScrollSteps: Sendable {
    public static let threshold = 12.0
    private var gathered = 0.0

    public init() {}

    /// Positive `delta` scrolls up.
    public mutating func steps(for delta: Double, isPrecise: Bool) -> Int {
        guard isPrecise else { return delta > 0 ? 1 : delta < 0 ? -1 : 0 }
        if (gathered > 0 && delta < 0) || (gathered < 0 && delta > 0) {
            gathered = 0
        }
        gathered += delta
        let steps = Int(gathered / Self.threshold)
        gathered -= Double(steps) * Self.threshold
        return steps
    }

    /// A new gesture begins.
    public mutating func reset() {
        gathered = 0
    }
}
