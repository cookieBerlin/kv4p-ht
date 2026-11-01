import Foundation

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
    public internal(set) var fromCallsign: String?
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
}

/// The APRS events of the receive path, derived like java-aprs `AprsController.handle` with no callsign configured:
/// nothing is acknowledged, digipeated or gated.
public struct APRSEventLog: Sendable {
    /// Repeats within this window count as the same event.
    static let duplicateWindowMs: Int64 = 30_000
    /// Numbered messages are retried for longer.
    static let numberedMessageDuplicateWindowMs: Int64 = 30 * 60_000

    public private(set) var events: [APRSEvent] = []
    /// All packets received, including those without an event (acknowledgements, faulty packets).
    public private(set) var packetCount = 0

    public init() {}

    /// A packet received over RF; returns the new or updated event.
    @discardableResult
    public mutating func receive(_ packet: APRSPacket, atMs now: Int64) -> APRSEvent? {
        packetCount += 1
        guard let candidate = Self.event(for: packet, at: now) else { return nil }
        let window =
            candidate.kind == .message && !Java.isBlank(candidate.messageIdentifier)
            ? Self.numberedMessageDuplicateWindowMs : Self.duplicateWindowMs
        let since = candidate.lastSeenMs - window
        // A new event is only created once the previous one left the window, so the newest match is the last.
        let match = events.lastIndex { $0.dedupKey == candidate.dedupKey }.flatMap {
            events[$0].lastSeenMs >= since ? $0 : nil
        }
        guard let index = match else {
            var event = candidate
            event.id = Int64(events.count + 1)
            event.packetCount = 1
            events.append(event)
            return event
        }
        events[index].relayCallsign = candidate.relayCallsign
        events[index].packetCount += 1
        events[index].lastSeenMs = max(candidate.lastSeenMs, now)
        return events[index]
    }

    /// `parseEvent`; `nil` for acknowledgements, rejections and faulty packets.
    static func event(for received: APRSPacket, at now: Int64) -> APRSEvent? {
        var packet = received
        var relay: String?
        if let inner = received.info.thirdParty {
            guard !inner.hasFault else { return nil }
            packet = inner
            relay = received.source
        }
        let info = packet.info
        if let message = info.message, message.isAck || message.isRej {
            return nil  // no outgoing messages yet, so nothing is delivered
        }
        var event = APRSEvent(firstSeenMs: now, lastSeenMs: now, fromCallsign: packet.source, relayCallsign: relay)
        if let position = info.position ?? info.object?.position {
            event.kind = .position
            event.latitude = position.position.latitude
            event.longitude = position.position.longitude
        }
        event.comment = [info.position?.comment, info.object?.comment, nil].reduce(
            first(packet.comment, info.comment)
        ) { first($0, $1) }
        if let weather = info.weather {
            event.kind = .weather
            event.temperature = Double(weather.temperature ?? 0)
            event.humidity = weather.humidity ?? 0
            event.pressure = weather.pressure ?? 0
            event.rain = weather.rainLast24Hours ?? 0
            event.snow = weather.snowfallLast24Hours ?? 0
            event.windForce = weather.windSpeed ?? 0
            event.windDirection = weather.windDirection.map(cardinal) ?? ""
        } else {
            apply(info, to: &event)
        }
        guard !packet.hasFault else { return nil }
        if event.kind == .unknown {
            event.comment = "Raw: " + Java.latin1(info.payload)
        }
        event.dedupKey = "\(packet.source)|\(packet.destination)|" + Data(info.payload).base64EncodedString()
        return event
    }

    /// Objects, messages, status and capabilities (`applyPayload` without weather).
    private static func apply(_ info: InformationField, to event: inout APRSEvent) {
        if info.payload[0] == UInt8(ascii: ";") {
            event.kind = .object
            event.objectName = info.object?.name
        }
        if let message = info.message {
            event.kind = .message
            event.toCallsign = message.target
            event.messageIdentifier = message.number
            event.body = message.body
        }
        if let status = info.status {
            event.kind = .status
            event.comment = status.text
        }
        if let capabilities = info.capabilities {
            event.kind = .stationCapabilities
            event.comment = capabilities.displayText
        }
    }

    /// `firstComment`: the preferred comment unless it is blank.
    private static func first(_ preferred: String?, _ fallback: String?) -> String? {
        Java.isBlank(preferred) ? fallback : preferred
    }

    /// `Utilities.degressToCardinal`.
    static func cardinal(_ degrees: Int) -> String {
        let bounds: [(Double, String)] = [
            (11.25, "N"), (33.75, "NNE"), (56.25, "NE"), (78.25, "ENE"), (101.25, "E"), (123.75, "ESE"),
            (146.25, "SE"), (168.75, "SSE"), (191.25, "S"), (213.75, "SSW"), (236.25, "SW"), (258.75, "WSW"),
            (281.25, "W"), (303.75, "WNW"), (326.25, "NW"), (348.75, "NNW"),
        ]
        return bounds.first { Double(degrees) < $0.0 }?.1 ?? "N"
    }
}
