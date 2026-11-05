import Foundation

/// The APRS list as a file (ADR-0057). The text is fixed in its units and language, as a file goes elsewhere.
public enum APRSExport {
    public enum Format: CaseIterable, Sendable {
        case csv, raw

        public var label: String {
            switch self {
            case .csv: "CSV"
            case .raw: "Raw packets"
            }
        }

        public var fileName: String {
            switch self {
            case .csv: "aprs-packets.csv"
            case .raw: "aprs-packets.txt"
            }
        }

        public func text(of events: [APRSEvent]) -> String {
            switch self {
            case .csv: APRSExport.csv(events)
            case .raw: APRSExport.rawLines(events)
            }
        }
    }

    private static let locale = Locale(identifier: "en_US_POSIX")
    private static let header = [
        "Time", "From", "To", "Type", "Latitude", "Longitude", "Symbol", "Device", "Text", "Internet only", "Packet",
    ]

    /// RFC 4180, with the header first.
    static func csv(_ events: [APRSEvent]) -> String {
        ([header.joined(separator: ",")] + events.map(line)).map { $0 + "\r\n" }.joined()
    }

    /// One packet per line, as it came.
    static func rawLines(_ events: [APRSEvent]) -> String {
        events.compactMap(\.rawLine).map { $0 + "\n" }.joined()
    }

    private static func line(_ event: APRSEvent) -> String {
        let hasPosition = event.latitude != 0 || event.longitude != 0
        // The coordinates are numbers of this app, and a negative one is no formula.
        let coordinates = [event.latitude, event.longitude].map {
            hasPosition ? String(format: "%.5f", locale: locale, $0) : ""
        }
        let before = [
            Date(timeIntervalSince1970: Double(event.lastSeenMs) / 1000).ISO8601Format(),
            event.fromCallsign,
            event.toCallsign ?? "",
            event.typeName,
        ].map(field)
        let after = [
            event.symbol?.codeText ?? "",
            event.deviceName ?? "",
            event.text(units: .metric, locale: locale) ?? "",
            event.isInternetOnly ? "yes" : "no",
            event.rawLine ?? "",
        ].map(field)
        return (before + coordinates + after).joined(separator: ",")
    }

    /// Quotes what needs it. Text from the air that a spreadsheet would run as a formula gets a `'` in front.
    static func field(_ value: String) -> String {
        let isFormula = value.first.map { "=+-@\t\r".contains($0) } == true
        let safe = isFormula ? "'" + value : value
        guard safe.contains(where: { ",\"\n\r".contains($0) }) else { return safe }
        return "\"" + safe.replacing("\"", with: "\"\"") + "\""
    }
}
