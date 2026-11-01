/// Why a frame or line is not an APRS packet at all (java-aprs throws).
public enum APRSParseError: Error, Equatable, Sendable {
    case invalidFrame
    case invalidLine
}

/// Parses APRS packets like java-aprs `Parser`, the parser of the Android app.
public enum APRSParser {
    /// `Parser.parseAX25`: an AX.25 UI frame without FCS, as the radio delivers it in a KISS DATA frame.
    public static func parse(ax25 frame: [UInt8]) throws(APRSParseError) -> APRSPacket {
        guard frame.count >= 16 else { throw .invalidFrame }
        let destination = AX25Address(ax25: frame[0..<7])
        let source = AX25Address(ax25: frame[7..<14])
        var position = 14
        var digipeaters: [AX25Address] = []
        while frame[position - 1] & 1 == 0 {
            guard frame.count - position >= 7 else { throw .invalidFrame }
            digipeaters.append(AX25Address(ax25: frame[position..<position + 7]))
            position += 7
        }
        guard frame.count - position >= 3, frame[position] == 0x03, frame[position + 1] == 0xF0 else {
            throw .invalidFrame
        }
        return try parseBody(
            source: address(source),
            destination: address(destination),
            digipeaters: digipeaters,
            body: Array(frame[(position + 2)...])
        )
    }

    /// `Parser.parse`: a TNC2 line such as `N0CALL>APRS,WIDE1-1:>status`.
    public static func parse(tnc2 line: String) throws(APRSParseError) -> APRSPacket {
        let bytes = Java.latin1Bytes(line)
        guard let arrow = bytes.firstIndex(of: UInt8(ascii: ">")), let colon = bytes.firstIndex(of: UInt8(ascii: ":")),
            colon > arrow, colon + 1 < bytes.count
        else { throw .invalidLine }
        let path = Java.split(Java.latin1(bytes[(arrow + 1)..<colon]), ",")
        guard let destination = path.first else { throw .invalidLine }
        var digipeaters: [AX25Address] = []
        for text in path.dropFirst().map(Java.trim) where !text.isEmpty {
            guard let address = AX25Address(text) else { throw .invalidLine }
            digipeaters.append(address)
        }
        do {
            return try parseBody(
                source: Java.latin1(bytes[..<arrow]),
                destination: destination,
                digipeaters: digipeaters,
                body: Array(bytes[(colon + 1)...])
            )
        } catch {
            throw .invalidLine
        }
    }

    /// `Parser.parseBody`: the information field by its data type identifier.
    static func parseBody(
        source: String,
        destination: String,
        digipeaters: [AX25Address],
        body: [UInt8]
    ) throws(APRSParseError) -> APRSPacket {
        var packet = APRSPacket(source: source, destination: destination, digipeaters: digipeaters, payload: body)
        let dti = body[0]
        if (UInt8(ascii: "A")...UInt8(ascii: "S")).contains(dti)
            || (UInt8(ascii: "U")...UInt8(ascii: "Z")).contains(dti)
            || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(dti)
        {
            packet.isFaulty = true
            packet.comment = "Invalid DTI"
            return packet
        }
        switch Unicode.Scalar(dti) {
        case "/", "@":
            let timestamp = try TimeField(body)
            packet.info.timestampHasFault = timestamp.hasFault
            let position = PositionField(body, destination: packet.destination, cursor: timestamp.cursor + 1)
            packet.info.position = position
            if position.position.symbolCode == UInt16(ascii: "_") {
                packet.info.weather = WeatherParser.parse(body, cursor: position.cursor)
            }
        case "!", "=", "`", "'", "$":
            guard !body.starts(with: Array("$ULTW".utf8)) else { break }
            let position = PositionField(body, destination: packet.destination, cursor: 1)
            packet.info.position = position
            if position.position.symbolCode == UInt16(ascii: "_"), body.count > 20 {
                packet.info.weather = WeatherParser.parse(body, cursor: position.cursor)
            }
        case ";":
            if body.count > 29 {
                let object = ObjectField(body)
                packet.info.object = object
                packet.comment = object.comment
            } else {
                packet.isFaulty = true
            }
        case ">":
            packet.info.status = StatusField(body)
        case "<":
            packet.info.capabilities = StationCapabilitiesField(body)
        case "T":
            packet.isFaulty = body.count <= 18
        case "#", "*", "_":
            packet.info.weather = WeatherParser.parse(body, cursor: 0)
        case "}":
            if var inner = try? parse(tnc2: Java.latin1(body.dropFirst())) {
                inner.digipeaters.append(AX25Address(call: packet.source))
                packet.info.thirdPartyStorage = [inner]
            } else {
                packet.isFaulty = true
            }
        case ":", "?", ")", "{":
            break
        default:
            packet.isFaulty = true
        }
        return packet
    }

    private static func address(_ address: AX25Address) -> String {
        address.callsign + (address.ssid.isEmpty ? "" : "-" + address.ssid)
    }
}
