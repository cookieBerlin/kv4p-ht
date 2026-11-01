import Foundation

/// A position with its APRS symbol (java-aprs `Position`).
public struct Position: Equatable, Sendable {
    private let rawLatitude: Double
    private let rawLongitude: Double
    public let ambiguity: Int
    /// Java `char` values of the symbol table and code.
    public let symbolTable: UInt16
    public let symbolCode: UInt16

    /// Coordinates are kept to five decimals, as java-aprs does.
    init(latitude: Double, longitude: Double, ambiguity: Int = 0, symbolTable: UInt16, symbolCode: UInt16) {
        rawLatitude = Java.round(latitude * 100_000) * 0.000_01
        rawLongitude = Java.round(longitude * 100_000) * 0.000_01
        self.ambiguity = ambiguity
        self.symbolTable = symbolTable
        self.symbolCode = symbolCode
    }

    /// `new Position(0, 0)`.
    static let unknown = Position(
        latitude: 0,
        longitude: 0,
        symbolTable: UInt16(ascii: "\\"),
        symbolCode: UInt16(ascii: ".")
    )

    /// `getLatitude()`: formatted with five decimals and parsed again.
    public var latitude: Double { Self.fiveDecimals(rawLatitude) }
    public var longitude: Double { Self.fiveDecimals(rawLongitude) }

    private static func fiveDecimals(_ value: Double) -> Double {
        strtod(String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), value), nil)
    }
}

/// The position of a report or object (java-aprs `PositionField`), including its quirks: on errors the comment
/// reads `null INVALID position format.`, and the comment starts at a fixed cursor.
public struct PositionField: Equatable, Sendable {
    public private(set) var position = Position.unknown
    /// `Uncompressed`, `Compressed`, `MICe`, `NMEA`, `Who knows...` or `Unknown`.
    public private(set) var source = "Unknown"
    public private(set) var comment: String?
    public private(set) var hasFault = false
    /// Where the data after the position (weather) starts.
    private(set) var cursor = 0

    init(_ body: [UInt8], destination: String, cursor start: Int) {
        do {
            try parse(body, destination: destination, cursor: start)
        } catch {
            hasFault = true
            comment = (comment ?? "null") + " INVALID position format."
        }
    }

    private mutating func parse(_ body: [UInt8], destination: String, cursor start: Int) throws(PositionError) {
        var cursor = start
        switch body[0] {
        case UInt8(ascii: "'"), UInt8(ascii: "`"):
            position = try PositionParser.micE(body, destination: destination)
            source = "MICe"
            cursor = 10
            if cursor < body.count, [UInt8(ascii: ">"), UInt8(ascii: "]"), UInt8(ascii: "`")].contains(body[cursor]) {
                cursor += 1
            }
            if cursor < body.count, body[cursor] == UInt8(ascii: "\"") {
                cursor += 4
            }
        case UInt8(ascii: "!"), UInt8(ascii: "="), UInt8(ascii: "/"), UInt8(ascii: "@"):
            if body[0] == UInt8(ascii: "!"), try Self.isUltimeter(body) {
                break  // Ultimeter weather station: no position
            }
            if body.count < 10 {
                hasFault = true
                comment = (comment ?? "null") + " Packet too short."
                try parseNMEA(body)  // java-aprs falls through to the NMEA case
            } else {
                cursor = try parseReport(body, cursor: cursor)
            }
        default:  // `$`, the only other type the parser hands over
            try parseNMEA(body)
        }
        if position.symbolCode != UInt16(ascii: "_"), cursor > 0, cursor < body.count {
            comment = Java.utf8(body[cursor...])
        }
        self.cursor = cursor
    }

    /// `!`, `=`, `/` and `@` with at least 10 bytes: compressed or uncompressed.
    private mutating func parseReport(_ body: [UInt8], cursor: Int) throws(PositionError) -> Int {
        let symbolTable = Java.char(body[cursor])
        if PositionParser.isCompressedSymbolTable(symbolTable) {
            position = try PositionParser.compressed(body, cursor: cursor)
            source = "Compressed"
            return cursor + 13
        }
        guard (UInt16(ascii: "0")...UInt16(ascii: "9")).contains(symbolTable) else {
            source = "Who knows..."
            hasFault = true
            return cursor
        }
        do throws(PositionError) {
            position = try PositionParser.uncompressed(body, cursor: cursor)
        } catch {
            comment = error.message
            hasFault = true
        }
        source = "Uncompressed"
        return cursor + 19
    }

    /// The `$` case: an NMEA sentence, or a fault when it is too short.
    private mutating func parseNMEA(_ body: [UInt8]) throws(PositionError) {
        guard body.count > 10 else {
            hasFault = true
            return
        }
        position = try PositionParser.nmea(body)
        source = "NMEA"
    }

    /// `msgBody[1] == 'U' && msgBody[2] == 'L' && msgBody[3] == 'T'`, which throws past the end like Java.
    private static func isUltimeter(_ body: [UInt8]) throws(PositionError) -> Bool {
        for (offset, letter) in "ULT".utf8.enumerated() {
            guard offset + 1 < body.count else { throw PositionError("index out of bounds") }
            if body[offset + 1] != letter {
                return false
            }
        }
        return true
    }
}

/// A position java-aprs cannot parse; `message` is what `getMessage()` returns.
struct PositionError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}
