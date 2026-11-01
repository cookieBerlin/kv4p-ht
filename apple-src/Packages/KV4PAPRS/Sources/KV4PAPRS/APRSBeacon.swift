import Foundation

/// A position report to transmit (java-aprs `BeaconData`, without weather, which the app does not send).
public struct APRSBeacon: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    /// `/` when `nil`.
    public var symbolTable: Character?
    /// `>` when `nil`.
    public var symbolCode: Character?
    /// `=` instead of `!`: the station can receive messages.
    public var isMessagingCapable: Bool
    public var isCompressed: Bool
    public var altitudeMeters: Double?
    public var speedKnots: Double?
    public var courseDegrees: Int?
    public var comment: String?

    public init(
        latitude: Double,
        longitude: Double,
        symbolTable: Character? = nil,
        symbolCode: Character? = nil,
        isMessagingCapable: Bool = true,
        isCompressed: Bool = true,
        altitudeMeters: Double? = nil,
        speedKnots: Double? = nil,
        courseDegrees: Int? = nil,
        comment: String? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.symbolTable = symbolTable
        self.symbolCode = symbolCode
        self.isMessagingCapable = isMessagingCapable
        self.isCompressed = isCompressed
        self.altitudeMeters = altitudeMeters
        self.speedKnots = speedKnots
        self.courseDegrees = courseDegrees
        self.comment = comment
    }

    /// `isValidBeacon`.
    var isValid: Bool {
        guard latitude.isFinite, (-90...90).contains(latitude), longitude.isFinite, (-180...180).contains(longitude),
            (courseDegrees == nil) == (speedKnots == nil),
            !isCompressed || (courseDegrees == nil && altitudeMeters == nil)
        else { return false }
        return Self.inRange(courseDegrees.map(Double.init), 0...360) && Self.inRange(speedKnots, 0...999)
            && Self.inRange(altitudeMeters.map { $0 * 3.28084 }, 0...999_999)
    }

    /// `isRoundedInRange`.
    private static func inRange(_ value: Double?, _ range: ClosedRange<Double>) -> Bool {
        value.map { $0.isFinite && range.contains(Java.round($0)) } ?? true
    }

    /// `encodeBeacon`: the information field.
    var payload: String {
        let table = symbolTable ?? "/"
        let code = symbolCode ?? ">"
        var text = isMessagingCapable ? "=" : "!"
        if isCompressed {
            text += Self.compressed(latitude, longitude, table: table, code: code)
        } else {
            text +=
                Self.degreesMinutes(latitude, isLatitude: true) + String(table)
                + Self.degreesMinutes(longitude, isLatitude: false) + String(code)
        }
        if let courseDegrees, let speedKnots {
            text += String(format: "%03d/%03d", courseDegrees, Int(Java.round(speedKnots)))
        }
        if let altitudeMeters {
            text += String(format: "/A=%06d", Int(Java.round(altitudeMeters * 3.28084)))
        }
        return text + (comment ?? "")
    }

    /// `Position.getDMS` without ambiguity: `DDMM.hhN` or `DDDMM.hhW`.
    private static func degreesMinutes(_ degrees: Double, isLatitude: Bool) -> String {
        let hundredths = Int(Java.round(degrees * 6000))
        let magnitude = abs(hundredths)
        let whole = magnitude / 6000
        let minutes = (magnitude / 100) % 60
        let sign = hundredths < 0 ? (isLatitude ? "S" : "W") : (isLatitude ? "N" : "E")
        return String(format: isLatitude ? "%02d%02d.%02d" : "%03d%02d.%02d", whole, minutes, magnitude % 100) + sign
    }

    /// `Position.toCompressedString`: base-91 digits of the position rounded to five decimals, `csT` unused.
    private static func compressed(_ latitude: Double, _ longitude: Double, table: Character, code: Character) -> String
    {
        let rounded = { (value: Double) in Java.round(value * 100_000) * 0.000_01 }
        let latitudeValue = Int(Java.round(380_926 * (90 - rounded(latitude))))
        let longitudeValue = Int(Java.round(190_463 * (180 + rounded(longitude))))
        let digits = { (value: Int) in
            [value / (91 * 91 * 91), value % (91 * 91 * 91) / (91 * 91), value % (91 * 91) / 91, value % 91]
                .map { Character(Unicode.Scalar(UInt8($0 + 33))) }
        }
        return String(table) + String(digits(latitudeValue)) + String(digits(longitudeValue)) + String(code) + " sT"
    }
}
