/// Which events the APRS tab shows (Android `AprsFeedPolicy` destination filter).
public enum APRSDestinationFilter: String, CaseIterable, Codable, Sendable {
    case all
    /// Messages from or to this station, to everyone (`ALL`, `QST`, `CQ`) and bulletins; all other events.
    case mine

    /// `isVisibleToMine` for `.mine`.
    public func shows(_ event: APRSEvent, callsign: String) -> Bool {
        guard self == .mine, event.kind == .message else { return true }
        let local = Self.normalize(callsign)
        let from = Self.normalize(event.fromCallsign)
        let destination = Self.normalize(event.toCallsign ?? "")
        return local == from || local == destination || ["ALL", "QST", "CQ"].contains(destination)
            || destination.hasPrefix("BLN")
    }

    /// `normalizeMessageCallsign`: trimmed, upper case, without an `-0` SSID.
    static func normalize(_ callsign: String) -> String {
        let normalized = Java.trim(callsign).uppercased()
        return normalized.hasSuffix("-0") ? String(normalized.dropLast(2)) : normalized
    }
}
