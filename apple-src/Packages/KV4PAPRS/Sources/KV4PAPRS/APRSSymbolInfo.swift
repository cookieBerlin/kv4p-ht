/// How a symbol is shown: a character of the system's fonts, or a system image (ADR-0054).
public enum APRSSymbolIcon: Equatable, Sendable {
    case character(String)
    case system(String)
}

/// A received or own APRS symbol: its table and code, and what they mean.
public struct APRSSymbolInfo: Equatable, Sendable {
    public let tableCharacter: Character
    public let code: Character

    public init(table: Character, code: Character) {
        tableCharacter = table
        self.code = code
    }

    /// Java `char` values, as `Position` keeps them; they come from single bytes of a packet.
    init(javaTable: UInt16, javaCode: UInt16) {
        self.init(
            table: Character(Unicode.Scalar(UInt8(truncatingIfNeeded: javaTable))),
            code: Character(Unicode.Scalar(UInt8(truncatingIfNeeded: javaCode)))
        )
    }

    /// A letter or digit in place of the table marks a symbol of the alternate table; in a compressed position, `a`
    /// to `j` stand for the digits.
    public var overlay: Character? {
        guard let value = tableCharacter.asciiValue else { return nil }
        switch tableCharacter {
        case "0"..."9", "A"..."Z": return tableCharacter
        case "a"..."j": return Character(Unicode.Scalar(value - UInt8(ascii: "a") + UInt8(ascii: "0")))
        default: return nil
        }
    }

    /// The table and code as they stand in the packet.
    public var codeText: String { "\(tableCharacter)\(code)" }

    /// `nil` for an unused code.
    public var name: String? { entry?.name }

    /// `nil` for an unused code.
    public var icon: APRSSymbolIcon? { entry?.icon }

    private var entry: (name: String, icon: APRSSymbolIcon)? {
        Self.table["\(overlay == nil ? tableCharacter : "\\")\(code)"]
    }
}

extension APRSSymbol {
    /// The icon of a beacon symbol, which are all in the primary table.
    public var icon: APRSSymbolIcon? { APRSSymbolInfo(table: "/", code: code).icon }
}
