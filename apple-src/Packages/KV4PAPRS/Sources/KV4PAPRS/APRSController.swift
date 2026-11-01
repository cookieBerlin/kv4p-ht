import Foundation

/// Why the controller asks to transmit (java-aprs `RfTransmissionPurpose`).
public enum APRSTransmitPurpose: String, Sendable {
    case acknowledgement = "ACKNOWLEDGEMENT"
    case reliableMessageRetry = "RELIABLE_MESSAGE_RETRY"
    case positionBeacon = "POSITION_BEACON"
    case outgoingMessage = "OUTGOING_MESSAGE"
    case broadcast = "BROADCAST"
    case digipeatedPacket = "DIGIPEATED_PACKET"
}

/// A packet the controller wants sent over RF; `frequencyHz` is `nil` for the current TX frequency.
public struct APRSTransmitRequest: Sendable {
    public let packet: APRSPacket
    public let frequencyHz: Int64?
    public let purpose: APRSTransmitPurpose
}

/// What the radio did with an `APRSTransmitRequest` (java-aprs `RfTransmission`).
public enum APRSTransmitOutcome: Equatable, Sendable {
    /// Queued for transmission on `frequencyHz` as `frame`.
    case accepted(frequencyHz: Int64, frame: [UInt8])
    /// Not now; a reliable message is retried later.
    case later
    /// Never, e.g. the radio moved to another frequency; a reliable message fails.
    case never
}

/// One packet received or sent (java-aprs `AprsPacket`).
public struct APRSPacketRecord: Equatable, Sendable {
    public enum Source: String, Sendable {
        case rxRF = "RX_RF"
        case txRF = "TX_RF"
    }

    public let source: Source
    public internal(set) var eventId: Int64?
    public let timestampMs: Int64
    public let frequencyHz: Int64?
    /// The digipeater path, e.g. `N1CALL*,WIDE2-1`; `nil` without one.
    public let path: String?
    public let frame: [UInt8]?
}

/// The APRS feed and messaging of the Android app (java-aprs `AprsController`): events from received packets,
/// outgoing messages with retries until acknowledged, and acknowledgements for messages to `callsign`.
///
/// Transmissions go through the `transmit` closure, which answers synchronously like `Callbacks.submitRf`.
/// Digipeating, beacons and APRS-IS are not implemented yet.
public struct APRSController: Sendable {
    static let duplicateWindowMs: Int64 = 30_000
    static let numberedMessageDuplicateWindowMs: Int64 = 30 * 60_000
    static let retryDelaysMs: [Int64] = [15_000, 30_000, 60_000, 120_000, 240_000]
    static let finalAcknowledgementGraceMs: Int64 = 30_000
    static let acknowledgementDelayMs: Int64 = 1_000
    static let messageIdentifierSpace: Int64 = 60_466_176  // 36^5

    /// The local callsign; empty disables messaging and acknowledgements.
    public var callsign: String {
        get { storedCallsign }
        set { storedCallsign = Java.trim(newValue).uppercased() }
    }
    /// The AX.25 destination of transmitted packets (the Android app uses `APKVPA`).
    public var txDestination: String {
        get { storedDestination }
        set { storedDestination = Java.trim(newValue).uppercased() }
    }
    public var txPath: [AX25Address] = []
    public private(set) var events: [APRSEvent] = []
    public private(set) var packets: [APRSPacketRecord] = []

    private var storedCallsign = ""
    private var storedDestination = ""
    private var pendingAcknowledgements: [(dueAtMs: Int64, eventId: Int64, packet: APRSPacket, frequencyHz: Int64?)] =
        []
    var nextMessageIdentifier: Int64

    /// `startMs` seeds the message identifiers, as java-aprs does with the clock.
    public init(startMs: Int64) {
        nextMessageIdentifier = startMs
    }

    // MARK: Receive

    /// `handle(packet, RX_RF, frequencyHz, frame)`; returns the new or updated event.
    @discardableResult
    public mutating func receive(_ packet: APRSPacket, frame: [UInt8]?, frequencyHz: Int64?, atMs now: Int64)
        -> APRSEvent?
    {
        let record = Self.record(packet, source: .rxRF, frequencyHz: frequencyHz, frame: frame, at: now)
        if let message = packet.info.thirdParty == nil ? packet.info.message : nil, message.isAck || message.isRej {
            return deliver(message, from: packet.source, record: record)
        }
        guard let candidate = Self.event(for: packet, at: now) else {
            packets.append(record)
            return nil
        }
        let event = persist(candidate, record: record, at: now)
        if event.kind == .message {
            acknowledge(event, frequencyHz: frequencyHz, at: now)
        }
        return event
    }

    /// An acknowledgement or rejection of one of our pending messages; others are only recorded.
    private mutating func deliver(_ response: MessageField, from remote: String, record: APRSPacketRecord) -> APRSEvent?
    {
        guard
            let index = events.lastIndex(where: {
                $0.fromCallsign == response.target && $0.toCallsign == remote
                    && $0.messageIdentifier == response.number && $0.deliveryState == .pending
            })
        else {
            packets.append(record)
            return nil
        }
        events[index].deliveryState = response.isAck ? .delivered : .rejected
        events[index].nextRetryAtMs = nil
        associate(record, with: index)
        return events[index]
    }

    private mutating func persist(_ candidate: APRSEvent, record: APRSPacketRecord, at now: Int64) -> APRSEvent {
        let window =
            candidate.kind == .message && !Java.isBlank(candidate.messageIdentifier)
            ? Self.numberedMessageDuplicateWindowMs : Self.duplicateWindowMs
        let since = candidate.lastSeenMs - window
        // A new event is only created once the previous one left the window, so the newest match is the last.
        let match = events.lastIndex { $0.dedupKey == candidate.dedupKey }.flatMap {
            events[$0].lastSeenMs >= since ? $0 : nil
        }
        guard let index = match else {
            return insert(candidate, record: record)
        }
        events[index].lastSeenMs = candidate.lastSeenMs
        events[index].relayCallsign = candidate.relayCallsign
        associate(record, with: index)
        return events[index]
    }

    private mutating func insert(_ candidate: APRSEvent, record: APRSPacketRecord) -> APRSEvent {
        var event = candidate
        event.id = Int64(events.count + 1)
        event.packetCount = 1
        events.append(event)
        var record = record
        record.eventId = event.id
        packets.append(record)
        return event
    }

    /// `associatePacket`: one more observation of the event.
    private mutating func associate(_ record: APRSPacketRecord, with index: Int, countsAsObservation: Bool = true) {
        var record = record
        record.eventId = events[index].id
        packets.append(record)
        if countsAsObservation {
            events[index].packetCount += 1
            events[index].lastSeenMs = max(events[index].lastSeenMs, record.timestampMs)
        }
    }

    /// `notifyAndAcknowledge`: every received copy of a numbered message to us is acknowledged after a second.
    private mutating func acknowledge(_ event: APRSEvent, frequencyHz: Int64?, at now: Int64) {
        guard !callsign.isEmpty, let to = event.toCallsign, Self.address(to) == Self.address(callsign),
            let identifier = event.messageIdentifier, !Java.isBlank(identifier), !txDestination.isEmpty
        else { return }
        let payload = MessageField.payload(to: event.fromCallsign, text: "ack" + identifier, identifier: nil)
        let packet = APRSPacket(source: callsign, destination: txDestination, digipeaters: txPath, payload: payload)
        pendingAcknowledgements.append((now + Self.acknowledgementDelayMs, event.id, packet, frequencyHz))
    }

    // MARK: Send

    /// `postMessage`: numbered (and retried) unless it goes to a bulletin, `ALL`, `QST` or `CQ`.
    public mutating func post(
        to recipient: String,
        text: String,
        frequencyHz: Int64?,
        atMs now: Int64,
        transmit: (APRSTransmitRequest) -> APRSTransmitOutcome
    ) -> Bool {
        let destination = Java.trim(recipient).uppercased()
        guard !callsign.isEmpty, !txDestination.isEmpty, !destination.isEmpty else { return false }
        let reliable = Self.requiresAcknowledgement(destination)
        let identifier = reliable ? nextIdentifier(for: destination) : nil
        let payload = MessageField.payload(to: destination, text: Java.trim(text), identifier: identifier)
        let packet = APRSPacket(source: callsign, destination: txDestination, digipeaters: txPath, payload: payload)
        let request = APRSTransmitRequest(
            packet: packet,
            frequencyHz: frequencyHz,
            purpose: reliable ? .outgoingMessage : .broadcast
        )
        guard case .accepted(let sentHz, let frame) = transmit(request) else { return false }
        var event = APRSEvent(
            kind: .message,
            firstSeenMs: now,
            lastSeenMs: now,
            dedupKey: Self.dedupKey(packet),
            fromCallsign: callsign,
            toCallsign: destination,
            body: MessageField(payload).body.map(Java.trim)
        )
        if reliable {
            event.messageIdentifier = identifier
            event.deliveryState = .pending
            event.transmitAttempts = 1
            event.nextRetryAtMs = now + Self.retryDelaysMs[0]
        }
        _ = insert(event, record: Self.record(packet, source: .txRF, frequencyHz: sentHz, frame: frame, at: now))
        return true
    }

    /// `requiresAcknowledgement`.
    public static func requiresAcknowledgement(_ destination: String) -> Bool {
        let normalized = Java.trim(destination).uppercased()
        return !normalized.hasPrefix("BLN") && !["ALL", "QST", "CQ"].contains(normalized)
    }

    /// `nextMessageIdentifier`: base 36 of a counter seeded with the start time, skipping ones still pending.
    private mutating func nextIdentifier(for destination: String) -> String {
        var identifier: String
        repeat {
            identifier = String(nextMessageIdentifier % Self.messageIdentifierSpace, radix: 36).uppercased()
            nextMessageIdentifier += 1
        } while events.contains { event in
            event.fromCallsign == callsign && event.toCallsign == destination
                && event.messageIdentifier == identifier && event.deliveryState == .pending
        }
        return identifier
    }

    // MARK: Housekeeping

    /// `tick`: due acknowledgements, then retries of pending messages. The Android app ticks every 500 ms.
    public mutating func tick(atMs now: Int64, transmit: (APRSTransmitRequest) -> APRSTransmitOutcome) {
        let due = pendingAcknowledgements.filter { $0.dueAtMs <= now }
        pendingAcknowledgements.removeAll { $0.dueAtMs <= now }
        for acknowledgement in due {
            let request = APRSTransmitRequest(
                packet: acknowledgement.packet,
                frequencyHz: acknowledgement.frequencyHz,
                purpose: .acknowledgement
            )
            if case .accepted(let sentHz, let frame) = transmit(request),
                let index = events.firstIndex(where: { $0.id == acknowledgement.eventId })
            {
                let record = Self.record(
                    acknowledgement.packet,
                    source: .txRF,
                    frequencyHz: sentHz,
                    frame: frame,
                    at: now
                )
                associate(record, with: index, countsAsObservation: false)
            }
        }
        for index in events.indices where events[index].deliveryState == .pending {
            if let next = events[index].nextRetryAtMs, next <= now {
                retryOrFail(index, at: now, transmit: transmit)
            }
        }
    }

    private mutating func retryOrFail(
        _ index: Int,
        at now: Int64,
        transmit: (APRSTransmitRequest) -> APRSTransmitOutcome
    ) {
        let event = events[index]
        guard event.transmitAttempts < Self.retryDelaysMs.count + 1,
            let original = packets.first(where: { $0.eventId == event.id && $0.source == .txRF }),
            let frame = original.frame, let packet = try? APRSParser.parse(ax25: frame)
        else { return fail(index) }
        let request = APRSTransmitRequest(
            packet: packet,
            frequencyHz: original.frequencyHz,
            purpose: .reliableMessageRetry
        )
        switch transmit(request) {
        case .accepted(let sentHz, let sentFrame):
            let record = Self.record(packet, source: .txRF, frequencyHz: sentHz, frame: sentFrame, at: now)
            let attempts = event.transmitAttempts + 1
            events[index].transmitAttempts = attempts
            events[index].nextRetryAtMs =
                now
                + (attempts >= Self.retryDelaysMs.count + 1
                    ? Self.finalAcknowledgementGraceMs : Self.retryDelaysMs[attempts - 1])
            associate(record, with: index)
        case .later:
            events[index].nextRetryAtMs = now + Self.retryDelaysMs[0]
        case .never:
            fail(index)
        }
    }

    private mutating func fail(_ index: Int) {
        events[index].deliveryState = .failed
        events[index].nextRetryAtMs = nil
    }

    // MARK: Events

    /// `parseEvent`; `nil` for faulty packets and third-party packets with a faulty inner packet.
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
            return nil  // an acknowledgement inside a third-party packet
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
        event.dedupKey = dedupKey(packet)
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

    /// `logicalPacketKey`: source, destination and payload.
    private static func dedupKey(_ packet: APRSPacket) -> String {
        "\(packet.source)|\(packet.destination)|" + Data(packet.info.payload).base64EncodedString()
    }

    private static func record(
        _ packet: APRSPacket,
        source: APRSPacketRecord.Source,
        frequencyHz: Int64?,
        frame: [UInt8]?,
        at now: Int64
    ) -> APRSPacketRecord {
        let path = packet.digipeaters.map(\.description).joined(separator: ",")
        return APRSPacketRecord(
            source: source,
            timestampMs: now,
            frequencyHz: frequencyHz,
            path: path.isEmpty ? nil : path,
            frame: frame
        )
    }

    /// `normalizeAx25Address`: SSID 0 is dropped.
    static func address(_ call: String) -> String {
        let normalized = Java.trim(call).uppercased()
        let parts = normalized.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count > 1, let ssid = Java.parseInt(parts[1]) else { return normalized }
        return ssid == 0 ? String(parts[0]) : "\(parts[0])-\(ssid)"
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
