import Foundation

/// The Java string and byte semantics java-aprs relies on, so the port behaves like the Android app.
enum Java {
    /// `(char) b` of a signed Java byte: bytes from 0x80 sign-extend to U+FF80…U+FFFF.
    static func char(_ byte: UInt8) -> UInt16 {
        UInt16(bitPattern: Int16(Int8(bitPattern: byte)))
    }

    /// `new String(bytes, ISO_8859_1)`: one character per byte.
    static func latin1(_ bytes: some Sequence<UInt8>) -> String {
        String(String.UnicodeScalarView(bytes.map { Unicode.Scalar($0) }))
    }

    /// `new String(bytes, US_ASCII)`: bytes from 0x80 become U+FFFD.
    static func ascii(_ bytes: some Sequence<UInt8>) -> String {
        String(String.UnicodeScalarView(bytes.map { $0 < 0x80 ? Unicode.Scalar($0) : "\u{FFFD}" }))
    }

    /// `new String(bytes, UTF-8)`: malformed sequences become U+FFFD.
    static func utf8(_ bytes: some Collection<UInt8>) -> String {
        String(decoding: bytes, as: UTF8.self)
    }

    /// `String.getBytes(ISO_8859_1)`: characters beyond U+00FF become `?`.
    static func latin1Bytes(_ text: String) -> [UInt8] {
        text.unicodeScalars.map { $0.value <= 0xFF ? UInt8($0.value) : UInt8(ascii: "?") }
    }

    /// `String.trim()`: drops leading and trailing characters up to U+0020.
    static func trim(_ text: String) -> String {
        let isTrimmed = { (scalar: Unicode.Scalar) in scalar.value <= 0x20 }
        let scalars = text.unicodeScalars.drop(while: isTrimmed).reversed().drop(while: isTrimmed).reversed()
        return String(String.UnicodeScalarView(scalars))
    }

    /// `"" + c` for a Java `char`.
    static func string(_ character: UInt16) -> String {
        String(utf16CodeUnits: [character], count: 1)
    }

    static func isBlank(_ text: String?) -> Bool {
        text.map { trim($0).isEmpty } ?? true
    }

    /// `String.split(",")` for a single literal character: trailing empty strings are removed.
    static func split(_ text: String, _ separator: Character) -> [String] {
        guard text.contains(separator) else { return [text] }
        var parts = text.split(separator: separator, omittingEmptySubsequences: false).map(String.init)
        while parts.last?.isEmpty == true {
            parts.removeLast()
        }
        return parts
    }

    /// `Integer.parseInt`: optional sign, digits, 32-bit range.
    static func parseInt(_ text: some StringProtocol) -> Int? {
        Int32(String(text)).map(Int.init)
    }

    /// `Math.round(double)` as `(long) floor(x + 0.5)`.
    static func round(_ value: Double) -> Double {
        (value + 0.5).rounded(.down)
    }
}

extension UInt16 {
    /// A Java `char` literal.
    init(ascii scalar: Unicode.Scalar) {
        self = UInt16(scalar.value)
    }
}
