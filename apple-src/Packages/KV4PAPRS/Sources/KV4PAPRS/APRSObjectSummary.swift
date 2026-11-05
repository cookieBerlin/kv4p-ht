/// Android `AprsObjectSummary`: a repeater object reads as frequencies, offset and range instead of its raw comment.
/// `aprs-object-summary.json` pins it to the Android code.
public struct APRSObjectSummary: Equatable, Sendable {
    public let cardText: String
    public let mapLabel: String

    nonisolated(unsafe) private static let historicSymbolPrefix =
        /(?i)^[^a-z0-9](?=(?:RNG\d{4}|R\d{1,4}[km]|\d{3,4}\.\d))/.wordBoundaryKind(.simple)
    nonisolated(unsafe) private static let historicLetterPrefix =
        /(?i)^[air]\s*(?=(?:RNG\d{4}|R\d{1,4}[km]))/.wordBoundaryKind(.simple)
    nonisolated(unsafe) private static let range = /(?i)\bRNG(\d{4})\b/.wordBoundaryKind(.simple)
    nonisolated(unsafe) private static let shortRange = /(?i)\bR(\d{1,4})([km])\b/.wordBoundaryKind(.simple)
    nonisolated(unsafe) private static let altitude = /(?i)\/A=(\d{6})\b/.wordBoundaryKind(.simple)
    nonisolated(unsafe) private static let offset = /(?i)([+-]\d+(?:\.\d+)?)\s*MHz\b/.wordBoundaryKind(.simple)
    nonisolated(unsafe) private static let frequencyPair =
        /\b(\d{3,4}(?:\.\d+)?)\s*\/\s*(\d{3,4}(?:\.\d+)?)\b/.wordBoundaryKind(.simple)
    nonisolated(unsafe) private static let frequency = /(?i)(\d{3,4}(?:\.\d+)?)\s*MHz\b/.wordBoundaryKind(.simple)
    nonisolated(unsafe) private static let bareFrequency = /\b(\d{3,4}(?:\.\d+)?)\s+(?=[+-]\d)/.wordBoundaryKind(
        .simple
    )
    nonisolated(unsafe) private static let mode = /\(([^)]{1,20})\)/
    nonisolated(unsafe) private static let whitespace = /\s+/

    /// What a part of the comment says, and the comment without it.
    private struct Extracted {
        var remaining: String
        var value = ""
    }

    public init(name: String?, comment: String?) {
        let name = Self.normalized(name ?? "")
        var remaining = Java.trim(comment ?? "")
        remaining = remaining.replacing(Self.historicSymbolPrefix, with: "", maxReplacements: 1)
        remaining = remaining.replacing(Self.historicLetterPrefix, with: "", maxReplacements: 1)
        let mode = remaining.firstMatch(of: Self.mode).map { String($0.output.1) } ?? ""

        let range = Self.extractRange(remaining)
        let altitude = Self.extract(Self.altitude, from: range.remaining) { "Altitude \(Self.decimal($0)) ft" }
        let frequencies = Self.extractFrequencies(altitude.remaining)
        let offset = Self.extract(Self.offset, from: frequencies.remaining, Self.formatOffset)

        let description = Self.cleanDescription(offset.remaining)
        let lines = [
            description,
            Self.join(frequencies.value, offset.value),
            Self.join(range.value, altitude.value),
        ].filter { !$0.isEmpty }
        cardText = lines.isEmpty ? Self.normalized(comment ?? "") : lines.joined(separator: "\n")
        mapLabel = [name, frequencies.value, Self.serviceName(mode, description)]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private static func extractRange(_ text: String) -> Extracted {
        if let match = text.firstMatch(of: range) {
            return Extracted(
                remaining: removing(match.range, from: text),
                value: "Range \(decimal(match.output.1)) mi"
            )
        }
        guard let match = text.firstMatch(of: shortRange) else { return Extracted(remaining: text) }
        let unit = match.output.2.lowercased() == "k" ? "km" : "mi"
        return Extracted(
            remaining: removing(match.range, from: text),
            value: "Range \(decimal(match.output.1)) \(unit)"
        )
    }

    private static func extractFrequencies(_ text: String) -> Extracted {
        if let pair = text.firstMatch(of: frequencyPair) {
            let value = "\(decimal(pair.output.1)) / \(decimal(pair.output.2)) MHz"
            return Extracted(remaining: removing(pair.range, from: text), value: value)
        }
        // Java looks behind for what may not stand before a frequency, which Swift's expressions cannot.
        let plain = text.matches(of: frequency).first { match in
            guard match.range.lowerBound > text.startIndex else { return true }
            let before = text[text.index(before: match.range.lowerBound)]
            return !(before.isNumber || before == "." || before == "+" || before == "-")
        }
        if let plain {
            return Extracted(remaining: removing(plain.range, from: text), value: "\(decimal(plain.output.1)) MHz")
        }
        return extract(bareFrequency, from: text) { "\(decimal($0)) MHz" }
    }

    private static func extract(
        _ pattern: Regex<(Substring, Substring)>,
        from text: String,
        _ format: (Substring) -> String
    ) -> Extracted {
        guard let match = text.firstMatch(of: pattern) else { return Extracted(remaining: text) }
        return Extracted(remaining: removing(match.range, from: text), value: format(match.output.1))
    }

    private static func removing(_ range: Range<String.Index>, from text: String) -> String {
        text[..<range.lowerBound] + " " + text[range.upperBound...]
    }

    private static func formatOffset(_ raw: Substring) -> String {
        let offset = decimal(raw)
        return offset.allSatisfy { $0 == "0" || $0 == "-" } ? "Simplex" : "Offset \(offset) MHz"
    }

    /// `BigDecimal.stripTrailingZeros().toPlainString()` for the numbers the patterns let through.
    private static func decimal(_ raw: Substring) -> String {
        let isNegative = raw.hasPrefix("-")
        let parts = raw.drop { $0 == "+" || $0 == "-" }.split(separator: ".", omittingEmptySubsequences: false)
        let whole = parts[0].drop { $0 == "0" }
        let fraction = parts.count > 1 ? String(parts[1].reversed().drop { $0 == "0" }.reversed()) : ""
        return (isNegative ? "-" : "") + (whole.isEmpty ? "0" : whole) + (fraction.isEmpty ? "" : ".\(fraction)")
    }

    private static func cleanDescription(_ value: String) -> String {
        let parts = value.map { $0 == "(" || $0 == ")" ? " " : $0 }
        return normalized(
            String(parts).split(separator: ",").map { Java.trim(String($0)) }.filter { !$0.isEmpty }
                .joined(separator: " · ")
        )
    }

    private static func serviceName(_ mode: String, _ description: String) -> String {
        let named = normalized(mode)
        if !named.isEmpty { return named }
        let text = description.lowercased()
        return [("winlink", "Winlink"), ("voice", "Voice"), ("data", "Data"), ("bbs", "BBS")]
            .first { text.contains($0.0) }?.1 ?? ""
    }

    private static func join(_ first: String, _ second: String) -> String {
        [first, second].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private static func normalized(_ value: String) -> String {
        Java.trim(value).replacing(whitespace, with: " ")
    }
}
