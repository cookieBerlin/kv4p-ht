/// What the APRS feed shows for one logical packet, observed one or more times (java-aprs `AprsEvent`).
public struct APRSEvent: Equatable, Identifiable, Sendable {
    /// `AprsEvent.*_TYPE`.
    public enum Kind: Int, Sendable {
        case unknown = 0
        case message = 1
        case object = 2
        case position = 3
        case weather = 4
        case status = 5
        case stationCapabilities = 6
    }

    public internal(set) var id: Int64 = 0
    public internal(set) var kind = Kind.unknown
    /// Milliseconds since 1970.
    public internal(set) var firstSeenMs: Int64
    public internal(set) var lastSeenMs: Int64
    public internal(set) var packetCount = 0
    /// Source, destination and payload: repeats of the same packet are one event.
    public internal(set) var dedupKey = ""
    public internal(set) var fromCallsign: String
    public internal(set) var toCallsign: String?
    public internal(set) var messageIdentifier: String?
    public internal(set) var body: String?
    public internal(set) var latitude = 0.0
    public internal(set) var longitude = 0.0
    public internal(set) var comment: String?
    public internal(set) var objectName: String?
    /// °F, %, hPa, inches, inches, mph.
    public internal(set) var temperature = 0.0
    public internal(set) var humidity = 0.0
    public internal(set) var pressure = 0.0
    public internal(set) var rain = 0.0
    public internal(set) var snow = 0.0
    public internal(set) var windForce = 0
    /// `N`, `NNE`, … or empty without a wind report.
    public internal(set) var windDirection: String?
    /// The station that relayed a third-party packet.
    public internal(set) var relayCallsign: String?
    /// This station digipeated the packet.
    public internal(set) var isDigipeated = false
    /// Only seen on APRS-IS, never on RF.
    public internal(set) var isInternetOnly = false
    /// Outgoing numbered messages wait for an acknowledgement.
    public internal(set) var deliveryState = DeliveryState.none
    public internal(set) var transmitAttempts = 0
    public internal(set) var nextRetryAtMs: Int64?

    /// `AprsEvent.DELIVERY_*`.
    public enum DeliveryState: Int, Sendable {
        case none = 0
        case pending = 1
        case delivered = 2
        case rejected = 3
        case failed = 4
    }
}
