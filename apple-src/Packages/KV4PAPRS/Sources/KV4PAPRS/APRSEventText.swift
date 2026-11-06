import Foundation

/// How each type of packet reads in the list (ADR-0055). The stored fields stay as the Android code gives them.
extension APRSEvent {
    /// What kind of packet this is, in a word.
    public var typeName: String {
        switch kind {
        case .message: isBulletin ? "Bulletin" : "Message"
        case .object: "Object"
        case .position: "Position"
        case .weather: "Weather"
        case .status: "Status"
        case .stationCapabilities: "Capabilities"
        case .unknown: unknownTypeName
        }
    }

    /// The main text of the row; `nil` if the packet says nothing more.
    public func text(units: APRSUnits, locale: Locale) -> String? {
        let text: String? =
            switch kind {
            case .message: body
            case .weather: weather.flatMap { Self.lines(of: $0, wind: windDirection, units: units, locale: locale) }
            case .object: objectSummary.cardText
            case .unknown: rawText
            default: displayComment
            }
        return text?.isEmpty == true ? nil : text
    }

    /// The text is the packet as it came, and best shown as code.
    public var isRawText: Bool { kind == .unknown }

    /// Says in a line what is not plain from the rest of the row.
    public var caption: String? {
        let type = [.status, .stationCapabilities, .unknown].contains(kind) || isBulletin ? typeName : nil
        let parts = [type, symbol?.name, deviceName].compactMap(\.self) + marks
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// A message to or from this callsign.
    public func isMessage(of callsign: String) -> Bool {
        guard kind == .message else { return false }
        let local = APRSDestinationFilter.normalize(callsign)
        return APRSDestinationFilter.normalize(fromCallsign) == local
            || toCallsign.map(APRSDestinationFilter.normalize) == local
    }

    /// The name the map gives its pin.
    public var mapLabel: String {
        kind == .object ? objectSummary.mapLabel : fromCallsign
    }

    /// All that is known, for a closer look.
    public var details: [String] {
        [typeName] + symbolDetails
    }

    /// Where the packet came from, or what became of it.
    public var marks: [String] {
        [
            isInternetOnly ? "Internet" : nil,
            isDigipeated ? "Digipeated" : nil,
            isRemovedObject ? "Removed" : nil,
        ].compactMap(\.self)
    }

    private var objectSummary: APRSObjectSummary {
        APRSObjectSummary(name: objectName, comment: comment)
    }

    private var isBulletin: Bool {
        guard kind == .message, let toCallsign else { return false }
        let destination = APRSDestinationFilter.normalize(toCallsign)
        return ["ALL", "QST", "CQ"].contains(destination) || destination.hasPrefix("BLN")
    }

    /// `Raw: ` is what the Android code puts before a packet it cannot read.
    private var rawText: String? {
        comment.map { String($0.dropFirst(Self.rawPrefix.count)) }
    }

    private static let rawPrefix = "Raw: "

    private var unknownTypeName: String {
        if rawText?.hasPrefix("T#") == true { return "Telemetry" }
        return rawText?.hasPrefix("?") == true ? "Query" : "Unknown packet"
    }

    /// What the station reported, as a 0 for the rest would say something else. No rain or snow is no news.
    private static func lines(of weather: WeatherField, wind: String?, units: APRSUnits, locale: Locale) -> String? {
        let first = [
            weather.temperature.map { units.temperature(Double($0), locale: locale) },
            weather.humidity.map { "\(APRSUnits.number($0, locale, digits: 0)) %" },
            weather.pressure.map { "\(APRSUnits.number($0, locale, digits: 0)) hPa" },
        ].compactMap(\.self).joined(separator: " · ")
        let second = [
            weather.windSpeed.map { speed in
                (["Wind", wind] + [units.speed(mph: Double(speed), locale: locale)]).compactMap(\.self).filter {
                    !$0.isEmpty
                }
                .joined(separator: " ")
            },
            weather.rainLast24Hours.flatMap { $0 > 0 ? "Rain \(units.rain(inches: $0, locale: locale))" : nil },
            weather.snowfallLast24Hours.flatMap { $0 > 0 ? "Snow \(units.snow(inches: $0, locale: locale))" : nil },
        ].compactMap(\.self).joined(separator: " · ")
        let lines = [first, second].filter { !$0.isEmpty }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}
