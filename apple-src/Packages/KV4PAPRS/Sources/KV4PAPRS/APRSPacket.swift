/// The kinds of data an information field carries (java-aprs `APRSTypes`, those the parser produces).
public enum APRSDataType: String, CaseIterable, Sendable {
    case timestamp = "T_TIMESTAMP"
    case position = "T_POSITION"
    case weather = "T_WX"
    case thirdParty = "T_THIRDPARTY"
    case object = "T_OBJECT"
    case status = "T_STATUS"
    case stationCapabilities = "T_STATCAPA"
}

/// A received APRS packet (java-aprs `APRSPacket`).
public struct APRSPacket: Equatable, Sendable {
    public var source: String
    public var destination: String
    public var digipeaters: [AX25Address]
    public var info: InformationField
    /// Set by the parser, e.g. `Invalid DTI` or the comment of an object.
    public var comment: String?
    var isFaulty = false

    init(source: String, destination: String, digipeaters: [AX25Address], payload: [UInt8]) {
        self.source = source.uppercased()
        self.destination = destination.uppercased()
        self.digipeaters = digipeaters
        info = InformationField(payload, destination: self.destination)
    }

    /// The data type identifier, the first byte of the information field.
    public var dti: UInt8 { info.payload[0] }

    public var hasFault: Bool { isFaulty || info.hasFault }
}

/// The information field and the data parsed from it (java-aprs `InformationField` and its `APRSData`).
public struct InformationField: Equatable, Sendable {
    public let payload: [UInt8]
    /// Always empty in java-aprs; kept because the event comment falls back to it.
    public let comment = ""
    /// `:` messages; `nil` for every other type.
    public let message: MessageField?
    public internal(set) var timestampHasFault: Bool?
    public internal(set) var position: PositionField?
    public internal(set) var weather: WeatherField?
    public internal(set) var object: ObjectField?
    public internal(set) var status: StatusField?
    public internal(set) var capabilities: StationCapabilitiesField?
    /// The packet a third-party (`}`) packet carries.
    public var thirdParty: APRSPacket? { thirdPartyStorage.first }
    var thirdPartyStorage: [APRSPacket] = []

    init(_ payload: [UInt8], destination: String) {
        self.payload = payload
        message = payload.first == UInt8(ascii: ":") ? MessageField(payload) : nil
    }

    public var types: Set<APRSDataType> {
        var types: Set<APRSDataType> = []
        let present: [(APRSDataType, Bool)] = [
            (.timestamp, timestampHasFault != nil), (.position, position != nil), (.weather, weather != nil),
            (.thirdParty, thirdParty != nil), (.object, object != nil), (.status, status != nil),
            (.stationCapabilities, capabilities != nil),
        ]
        for (type, isPresent) in present where isPresent {
            types.insert(type)
        }
        return types
    }

    /// Faults of the field and of all its data (`InformationField.hasFault`).
    public var hasFault: Bool {
        message?.hasFault == true || timestampHasFault == true || position?.hasFault == true
            || thirdParty?.hasFault == true
    }
}
