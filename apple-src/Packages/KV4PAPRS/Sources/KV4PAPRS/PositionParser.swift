import Foundation

/// Position formats of the APRS specification, ported from java-aprs `PositionParser` with its arithmetic (Mic-E and
/// compressed positions in `Float`, minutes in `Double`).
enum PositionParser {
    // MARK: Uncompressed

    /// `DDMM.hhN/DDDMM.hhW$`, with position ambiguity (spaces instead of digits).
    static func uncompressed(_ body: [UInt8], cursor: Int) throws(PositionError) -> Position {
        if body[0] == UInt8(ascii: "/") || body[0] == UInt8(ascii: "@") {
            // java-aprs reads the timestamp indicator even though it ignores the timestamp.
            _ = try byte(body, cursor + 6)
        }
        guard body.count >= cursor + 19 else { throw PositionError("Uncompressed packet too short") }
        var text = body[cursor..<cursor + 19].map(Java.char) + [UInt16](repeating: 0, count: body.count - cursor - 18)
        var ambiguity = 0
        let space = UInt16(ascii: " ")
        // Latitude, then longitude: each missing digit widens the area to its middle.
        let fills = [
            (2, UInt16(ascii: "3")), (3, UInt16(ascii: "5")), (5, UInt16(ascii: "5")), (6, UInt16(ascii: "5")),
        ]
        for offset in [0, 10] {
            for (level, (index, middle)) in fills.enumerated() where text[offset + index] == space {
                text[offset + index] = middle
                for later in fills.dropFirst(level + 1) {
                    text[offset + later.0] = UInt16(ascii: "0")
                }
                ambiguity = level + 1
            }
        }
        do throws(PositionError) {
            var latitude = try degreesMinutes(text, cursor: 0, degrees: 2, length: 7, decimalDot: true)
            let latitudeSign = text[7]
            let symbolTable = text[8]
            var longitude = try degreesMinutes(text, cursor: 9, degrees: 3, length: 8, decimalDot: true)
            let longitudeSign = text[17]
            let symbolCode = text[18]
            if latitudeSign == UInt16(ascii: "s") || latitudeSign == UInt16(ascii: "S") {
                latitude = 0 - latitude
            } else if latitudeSign != UInt16(ascii: "n"), latitudeSign != UInt16(ascii: "N") {
                throw PositionError("Bad latitude sign character")
            }
            if longitudeSign == UInt16(ascii: "w") || longitudeSign == UInt16(ascii: "W") {
                longitude = 0 - longitude
            } else if longitudeSign != UInt16(ascii: "e"), longitudeSign != UInt16(ascii: "E") {
                throw PositionError("Bad longitude sign character")
            }
            return Position(
                latitude: latitude,
                longitude: longitude,
                ambiguity: ambiguity,
                symbolTable: symbolTable,
                symbolCode: symbolCode
            )
        } catch {
            throw PositionError("java.lang.Exception: " + error.message)  // `new Exception(e)`
        }
    }

    // MARK: Compressed

    static func isCompressedSymbolTable(_ table: UInt16) -> Bool {
        table == UInt16(ascii: "/") || table == UInt16(ascii: "\\")
            || (UInt16(ascii: "A")...UInt16(ascii: "Z")).contains(table)
            || (UInt16(ascii: "a")...UInt16(ascii: "j")).contains(table)
    }

    /// `/YYYYXXXX$csT`: base-91 latitude and longitude.
    static func compressed(_ body: [UInt8], cursor: Int) throws(PositionError) -> Position {
        guard body.count >= cursor + 13 else { throw PositionError("Compressed position too short") }
        let digits = (1..<9).map { Int(Java.char(body[cursor + $0])) }
        guard digits.allSatisfy({ (0x21...0x7B).contains($0) }) else {
            throw PositionError("Compressed position characters out of range")
        }
        let values = digits.map { $0 - 33 }
        let latitudeValue = values[0] * 91 * 91 * 91 + values[1] * 91 * 91 + values[2] * 91 + values[3]
        let longitudeValue = values[4] * 91 * 91 * 91 + values[5] * 91 * 91 + values[6] * 91 + values[7]
        let latitude: Float = 90 - (Float(latitudeValue) / 380_926)
        let longitude: Float = -180 + (Float(longitudeValue) / 190_463)
        return Position(
            latitude: Double(latitude),
            longitude: Double(longitude),
            symbolTable: Java.char(body[cursor]),
            symbolCode: Java.char(body[cursor + 9])
        )
    }

    // MARK: Mic-E

    /// Latitude in the destination call, longitude in the information field.
    static func micE(_ body: [UInt8], destination: String) throws(PositionError) -> Position {
        let call = Array(destination.prefix { $0 != "-" }.utf16)
        guard call.count == 6 else { throw PositionError("MicE Destination Call incorrect length") }
        let digit = UInt16(ascii: "0")...UInt16(ascii: "9")
        for index in 1...3
        where
            !(digit ~= call[index] || (UInt16(ascii: "A")...UInt16(ascii: "L")) ~= call[index]
            || (UInt16(ascii: "P")...UInt16(ascii: "Z")) ~= call[index])
        {
            throw PositionError("Digit dorked")
        }
        for index in 4...5
        where
            !(digit ~= call[index] || call[index] == UInt16(ascii: "L")
            || (UInt16(ascii: "P")...UInt16(ascii: "Z")) ~= call[index])
        {
            throw PositionError("Digit dorked")
        }
        let ranges: [ClosedRange<UInt16>] = [
            0x26...0x7F, 0x26...0x61, 0x1C...0x7F, 0x1C...0x7F, 0x1C...0x7D, 0x1C...0x7F,
        ]
        for (offset, range) in ranges.enumerated() where !range.contains(Java.char(try byte(body, offset + 1))) {
            throw PositionError("Raw packet contains an invalid character")
        }
        let symbolCode = Java.char(try byte(body, 7))
        guard (0x21...0x7B).contains(symbolCode) || symbolCode == 0x7D else {
            throw PositionError("Raw packet contains an invalid character")
        }
        let symbolTable = Java.char(try byte(body, 8))
        guard isUncompressedSymbolTable(symbolTable) else { throw PositionError("Invalid symbol table") }

        var latitudeDigits = call.map { character -> UInt16 in
            switch character {
            case UInt16(ascii: "A")...UInt16(ascii: "J"): character - (UInt16(ascii: "A") - UInt16(ascii: "0"))
            case UInt16(ascii: "P")...UInt16(ascii: "Y"): character - (UInt16(ascii: "P") - UInt16(ascii: "0"))
            case UInt16(ascii: "K"), UInt16(ascii: "L"), UInt16(ascii: "Z"): UInt16(ascii: "_")
            default: character
            }
        }
        var ambiguity = 0
        let middles = [
            (5, UInt16(ascii: "5"), 4), (4, UInt16(ascii: "5"), 3), (3, UInt16(ascii: "5"), 2),
            (2, UInt16(ascii: "3"), 1),
        ]
        for (index, middle, level) in middles where latitudeDigits[index] == UInt16(ascii: "_") {
            latitudeDigits[index] = middle
            ambiguity = level
        }
        guard latitudeDigits[0] != UInt16(ascii: "_"), latitudeDigits[1] != UInt16(ascii: "_") else {
            throw PositionError("bad pos-ambiguity on destcall")
        }
        var latitude = try degreesMinutes(latitudeDigits, cursor: 0, degrees: 2, length: 9, decimalDot: false)
        if Array(destination.utf16)[3] <= UInt16(ascii: "L") {
            latitude = 0 - latitude
        }

        var degrees = Int(Java.char(body[1])) - 28
        if call[4] >= UInt16(ascii: "P") {
            degrees += 100
        }
        if (180...189).contains(degrees) {
            degrees -= 80
        } else if (190...199).contains(degrees) {
            degrees -= 190
        }
        var minutes = Int(Java.char(body[2])) - 28
        if minutes >= 60 {
            minutes -= 60
        }
        let hundredths = Int(Java.char(body[3])) - 28
        var longitude: Float =
            switch ambiguity {
            case 0: Float(degrees) + Float(minutes) / 60 + Float(hundredths) / 6000
            case 1: Float(degrees) + Float(minutes) / 60 + Float(hundredths - hundredths % 10 + 5) / 6000
            case 2: Float(degrees) + Float(minutes) / 60
            case 3: Float(degrees) + Float(minutes - minutes % 10 + 5) / 60
            default: Float(degrees) + 0.5
            }
        if call[5] >= UInt16(ascii: "P") {
            longitude = 0 - longitude
        }
        return Position(
            latitude: latitude,
            longitude: Double(longitude),
            ambiguity: ambiguity,
            symbolTable: symbolTable,
            symbolCode: symbolCode
        )
    }

    // MARK: NMEA

    /// `$GPRMC`, `$GPGGA`, `$GPGLL`, `$GPWPL` and `$PNTS` sentences.
    static func nmea(_ body: [UInt8]) throws(PositionError) -> Position {
        let fields = Java.split(Java.ascii(body), ",")
        guard fields.count >= 5 else { throw PositionError("Too few parts in NMEA sentence") }
        let coordinates: ArraySlice<String>
        switch fields[0] {
        case "$GPGGA" where fields.count >= 15:
            guard fields[6] == "1" else { throw PositionError("Not a valid position fix") }
            coordinates = fields[2...5]
        case "$GPGLL" where fields.count > 7:
            guard fields[6] == "A", fields[7].first == "A" else { throw PositionError("Not valid NMEA sentence") }
            coordinates = fields[1...4]
        case "$GPRMC" where fields.count > 11:
            guard fields[2] == "A" else { throw PositionError("Not valid NMEA sentence") }
            coordinates = fields[3...6]
        case "$GPWPL" where fields.count > 5:
            coordinates = fields[1...4]
        case "$PNTS" where fields.count > 15 && fields[1] == "1":
            coordinates = fields[7...10]
        default:
            throw PositionError("Invalid NMEA sentence")
        }
        let parts = Array(coordinates)
        var latitude = try degreesMinutes(Array(parts[0].utf16), cursor: 0, degrees: 2, length: 9, decimalDot: true)
        var longitude = try degreesMinutes(Array(parts[2].utf16), cursor: 0, degrees: 3, length: 9, decimalDot: true)
        guard latitude <= 90, longitude <= 180 else { throw PositionError("Coordinate too high") }
        switch parts[1] {
        case "S", "s": latitude = 0 - latitude
        case "N", "n": break
        default: throw PositionError("Bad latitude sign")
        }
        switch parts[3] {
        case "W", "w": longitude = 0 - longitude
        case "E", "e": break
        default: throw PositionError("Bad longitude sign")
        }
        return Position(
            latitude: latitude,
            longitude: longitude,
            symbolTable: UInt16(ascii: "/"),
            symbolCode: UInt16(ascii: ">")
        )
    }

    // MARK: Helpers

    /// `parseDegMin`: degrees, then minutes (with a decimal dot after two digits if `decimalDot`), five decimals.
    private static func degreesMinutes(
        _ text: [UInt16],
        cursor: Int,
        degrees: Int,
        length: Int,
        decimalDot: Bool
    ) throws(PositionError) -> Double {
        guard text.count >= cursor + degrees + 2 else { throw PositionError("Too short degmin data") }
        let digits = UInt16(ascii: "0")...UInt16(ascii: "9")
        var result = 0.0
        for character in text[cursor..<cursor + degrees] {
            guard digits ~= character else { throw PositionError("Bad input decimals:  " + Java.string(character)) }
            result = result * 10 + Double(character - UInt16(ascii: "0"))
        }
        var factor = 10.0
        var minutes = 0.0
        let count = min(text.count - degrees - cursor, length - degrees)
        for (index, character) in text[(cursor + degrees)...].prefix(count).enumerated() {
            if decimalDot, index == 2 {
                guard character == UInt16(ascii: ".") else { throw PositionError("Expected decimal dot") }
                continue
            }
            guard digits ~= character else { throw PositionError("Bad input decimals: " + Java.string(character)) }
            minutes += factor * Double(character - UInt16(ascii: "0"))
            factor *= 0.1
        }
        guard minutes < 60 else { throw PositionError("Bad minutes value - 60.0 or over") }
        result += minutes / 60
        result = Java.round(result * 100_000) * 0.000_01
        if degrees == 2, result > 90.01 {
            throw PositionError("Latitude value too high")
        }
        if degrees == 3, result > Double(Float(180.01)) {
            throw PositionError("Longitude value too high")
        }
        return result
    }

    private static func isUncompressedSymbolTable(_ table: UInt16) -> Bool {
        table == UInt16(ascii: "/") || table == UInt16(ascii: "\\")
            || (UInt16(ascii: "A")...UInt16(ascii: "Z")).contains(table)
            || (UInt16(ascii: "0")...UInt16(ascii: "9")).contains(table)
    }

    /// `msgBody[i]`, which throws past the end like Java.
    static func byte(_ body: [UInt8], _ index: Int) throws(PositionError) -> UInt8 {
        guard index < body.count else {
            throw PositionError("Index \(index) out of bounds for length \(body.count)")
        }
        return body[index]
    }
}
