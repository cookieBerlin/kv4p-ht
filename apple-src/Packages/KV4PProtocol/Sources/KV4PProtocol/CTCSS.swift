/// SA818 CTCSS tones as used in `HostDesiredState.ctcssTx`/`ctcssRx`, with the labels and input rules of the
/// Android `ToneHelper` (pinned by `ctcss.json`).
public enum CTCSS {
    /// Tone frequencies in Hz; tone index `n` is `frequencies[n - 1]`, index 0 is no tone.
    public static let frequencies: [Double] = [
        67, 71.9, 74.4, 77, 79.7, 82.5, 85.4, 88.5, 91.5, 94.8, 97.4, 100, 103.5, 107.2, 110.9, 114.8, 118.8, 123,
        127.3, 131.8, 136.5, 141.3, 146.2, 151.4, 156.7, 162.2, 167.9, 173.8, 179.9, 186.2, 192.8, 203.5, 210.7,
        218.1, 225.7, 233.6, 241.8, 250.3,
    ]

    public static let none = "None"

    /// Labels by tone index: `"None"`, `"67"`, `"71.9"`, …
    public static let labels = [none] + frequencies.map(label)

    public static func label(for index: UInt8) -> String? {
        labels.indices.contains(Int(index)) ? labels[Int(index)] : nil
    }

    /// The index of an entered tone after normalising it.
    public static func index(of tone: String) -> UInt8? {
        labels.firstIndex(of: normalize(tone)).map(UInt8.init)
    }

    /// The closest tone within 1 Hz, or `"None"`; `0` and `1` mean no tone.
    public static func normalize(_ tone: String) -> String {
        let trimmed = trimmed(tone)
        if labels.contains(trimmed) {
            return trimmed
        }
        guard let value = Double(trimmed), value != 0, value != 1 else { return none }
        var closest: Double?
        var smallest = Double.greatestFiniteMagnitude
        for frequency in frequencies {
            let distance = abs(value - frequency)
            if distance <= 1, distance < smallest {
                closest = frequency
                smallest = distance
            }
        }
        return closest.map(label) ?? none
    }

    /// Java `String.trim()`: drops leading and trailing characters up to U+0020.
    private static func trimmed(_ text: String) -> String {
        let isTrimmed = { (scalar: Unicode.Scalar) in scalar.value <= 0x20 }
        let scalars = text.unicodeScalars.drop(while: isTrimmed).reversed().drop(while: isTrimmed).reversed()
        return String(String.UnicodeScalarView(scalars))
    }

    /// `100` rather than `100.0`, as in Android.
    private static func label(_ frequency: Double) -> String {
        frequency == frequency.rounded() ? String(Int(frequency)) : String(frequency)
    }
}
