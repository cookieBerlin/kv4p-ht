import Foundation

/// A latitude or a longitude in decimal degrees, as the memory form shows and reads it (ADR-0065).
public enum Coordinate {
    /// To five decimals, about a metre, without trailing zeros; empty for none.
    public static func format(_ degrees: Double?, separator: String = ".") -> String {
        guard let degrees else { return "" }
        var text = String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), degrees)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return (text == "-0" ? "0" : text).replacing(".", with: separator)
    }

    /// `nil` for an empty field, NaN for one that is not a number.
    public static func parse(_ text: String) -> Double? {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return Double(text.replacing(",", with: ".")) ?? .nan
    }
}
