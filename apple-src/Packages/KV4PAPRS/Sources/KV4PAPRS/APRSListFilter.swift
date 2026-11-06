/// What an APRS list looks for (ADR-0057): remembered for each list on this device, and not synced.
public struct APRSListFilter: Codable, Equatable, Sendable {
    /// Found in the sender or the recipient, in any case.
    public var callsign: String
    /// The kinds of packet; none means all.
    public var kinds: Set<APRSEvent.Kind>
    /// Only messages from or to this station, with any SSID; not those to everyone.
    public var isForMe: Bool

    public init(callsign: String = "", kinds: Set<APRSEvent.Kind> = [], isForMe: Bool = false) {
        self.callsign = callsign
        self.kinds = kinds
        self.isForMe = isForMe
    }

    public var isEmpty: Bool {
        searchTerm.isEmpty && kinds.isEmpty && !isForMe
    }

    /// The callsign as it is looked for.
    public var searchTerm: String {
        Java.trim(callsign).uppercased()
    }

    public func matches(_ event: APRSEvent, ownCallsign: String) -> Bool {
        (kinds.isEmpty || kinds.contains(event.kind))
            && (searchTerm.isEmpty || event.callsigns.contains(searchTerm))
            && (!isForMe || event.isMessage(of: ownCallsign))
    }
}

extension APRSEvent {
    /// Sender and recipient in upper case, to look through both at once.
    public var callsigns: String {
        "\(fromCallsign) \(toCallsign ?? "")".uppercased()
    }

    /// A message from or to this station, with any SSID.
    public func isMessage(of callsign: String) -> Bool {
        let own = Self.baseCallsign(callsign)
        guard kind == .message, !own.isEmpty else { return false }
        return Self.baseCallsign(fromCallsign) == own || toCallsign.map(Self.baseCallsign) == own
    }

    /// A message meant for this station, with any SSID: not one to everyone, and not this station's own. Another of its
    /// SSIDs can write to it.
    public func isMessage(to callsign: String) -> Bool {
        let own = Self.baseCallsign(callsign)
        return kind == .message && !own.isEmpty && toCallsign.map(Self.baseCallsign) == own
            && fromCallsign.uppercased() != Java.trim(callsign).uppercased()
    }

    /// The callsign without its SSID, in upper case.
    public static func baseCallsign(_ callsign: String) -> String {
        String(Java.trim(callsign).uppercased().prefix { $0 != "-" })
    }
}

extension APRSEvent.Kind {
    /// In the order a filter offers them.
    public static let filterOptions: [APRSEvent.Kind] = [
        .message, .position, .object, .weather, .status, .stationCapabilities, .unknown,
    ]

    public var filterName: String {
        switch self {
        case .message: "Messages"
        case .position: "Positions"
        case .object: "Objects"
        case .weather: "Weather"
        case .status: "Status"
        case .stationCapabilities: "Capabilities"
        case .unknown: "Other"
        }
    }
}
