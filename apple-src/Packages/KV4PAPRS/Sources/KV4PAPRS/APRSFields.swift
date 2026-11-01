/// A `:` message (java-aprs `MessagePacket`).
public struct MessageField: Equatable, Sendable {
    public private(set) var target = ""
    public private(set) var body: String?
    public private(set) var number: String?
    public private(set) var isAck = false
    public private(set) var isRej = false
    public private(set) var hasFault = false

    init(_ payload: [UInt8]) {
        guard payload.count >= 2 else {
            hasFault = true
            return
        }
        guard let separator = payload.indices.dropFirst(2).first(where: { payload[$0] == UInt8(ascii: ":") }) else {
            target = "UNKNOWN"
            hasFault = true
            return
        }
        target = Java.trim(Java.latin1(payload[1..<separator])).uppercased()
        var text = Java.latin1(payload[(separator + 1)...])
        number = ""
        if let brace = payload.lastIndex(of: UInt8(ascii: "{")), brace > separator {
            number = Java.latin1(payload[(brace + 1)...])
            text = Java.latin1(payload[(separator + 1)..<brace])
        }
        body = text
        for (prefix, isAck) in [("ack", true), ("rej", false)] where text.lowercased().hasPrefix(prefix) {
            self.isAck = isAck
            isRej = !isAck
            number = String(text.dropFirst(3))
            body = String(text.prefix(3))
        }
    }
}

/// `>` status text (java-aprs `StatusField`), without a leading `DDHHMMz` timestamp.
public struct StatusField: Equatable, Sendable {
    public let text: String

    init(_ payload: [UInt8]) {
        let hasTimestamp =
            payload.count >= 8 && (payload[7] == UInt8(ascii: "z") || payload[7] == UInt8(ascii: "Z"))
            && payload[1...6].allSatisfy { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }
        let offset = hasTimestamp ? 8 : 1
        text = payload.count <= offset ? "" : Java.trim(Java.latin1(payload[offset...]))
    }
}

/// `<` station capabilities (java-aprs `StationCapabilitiesField`).
public struct StationCapabilitiesField: Equatable, Sendable {
    public private(set) var isIGate = false
    public private(set) var messageCount: Int?
    public private(set) var localStationCount: Int?
    public private(set) var displayText = ""

    init(_ payload: [UInt8]) {
        let rawText = payload.count <= 1 ? "" : Java.trim(Java.latin1(payload.dropFirst()))
        var unrecognized: [String] = []
        for token in Java.split(rawText, ",").map(Java.trim) where !token.isEmpty {
            let upper = token.uppercased()
            let value = token.firstIndex(of: "=").map { token[token.index(after: $0)...] }
            if upper == "IGATE" {
                isIGate = true
            } else if upper.hasPrefix("MSG_CNT=") {
                messageCount = Self.count(value)
                if messageCount == nil { unrecognized.append(token) }
            } else if upper.hasPrefix("LOC_CNT=") {
                localStationCount = Self.count(value)
                if localStationCount == nil { unrecognized.append(token) }
            } else {
                unrecognized.append(token)
            }
        }
        var parts: [String] = []
        if isIGate { parts.append("IGate") }
        if let messageCount { parts.append("\(messageCount) message" + (messageCount == 1 ? "" : "s")) }
        if let localStationCount {
            parts.append("\(localStationCount) local station" + (localStationCount == 1 ? "" : "s"))
        }
        parts += unrecognized
        displayText = parts.isEmpty ? rawText : parts.joined(separator: " · ")
    }

    private static func count(_ value: Substring?) -> Int? {
        value.flatMap { Java.parseInt(Java.trim(String($0))) }.flatMap { $0 < 0 ? nil : $0 }
    }
}

/// `;` object (java-aprs `ObjectField`): name, live or killed, and a position like a `!` report.
public struct ObjectField: Equatable, Sendable {
    public let name: String
    public let isLive: Bool
    public let position: PositionField
    public var comment: String? { position.comment }

    init(_ payload: [UInt8]) {
        name = Java.trim(Java.latin1(payload[1..<10]))
        isLive = payload[10] == UInt8(ascii: "*")
        position = PositionField([UInt8(ascii: "!")] + payload[18...], destination: "FOO", cursor: 1)
    }
}

/// The timestamp of `/` and `@` positions (java-aprs `TimeField`); only its length matters to the parser.
struct TimeField {
    /// Where the timestamp ends.
    let cursor: Int
    /// The packet is too short to hold a timestamp.
    let hasFault: Bool

    init(_ payload: [UInt8]) {
        hasFault = payload.count <= 7
        let indicator = hasFault ? UInt8(ascii: "z") : payload[7]
        cursor = (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(indicator) ? 8 : 7
    }
}
