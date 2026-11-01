import Foundation

/// APRS-IS login details of java-aprs `AprsIsClient`.
public enum APRSIS {
    public static let defaultServer = "rotate.aprs2.net:14580"
    static let defaultPort = 14580

    /// A server as `host:port`; IPv6 hosts in brackets.
    public struct Server: Equatable, Sendable, CustomStringConvertible {
        public let host: String
        public let port: Int

        /// `parseServer`: empty for the default server, `nil` for anything but `host[:port]`.
        public init?(_ text: String) {
            let candidate = Java.trim(text).isEmpty ? APRSIS.defaultServer : Java.trim(text)
            guard let components = URLComponents(string: "aprs://" + candidate), let host = components.host,
                !host.isEmpty, components.user == nil, components.password == nil, components.query == nil,
                components.fragment == nil, components.path.isEmpty
            else { return nil }
            let port = components.port ?? APRSIS.defaultPort
            guard (1...65_535).contains(port) else { return nil }
            self.host = host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
            self.port = port
        }

        public var description: String { (host.contains(":") ? "[\(host)]" : host) + ":\(port)" }
    }

    /// `normalizeCallsign`: trimmed, upper case, without `-0`.
    public static func normalize(_ callsign: String) -> String {
        let normalized = Java.trim(callsign).uppercased()
        return normalized.hasSuffix("-0") ? String(normalized.dropLast(2)) : normalized
    }

    /// The APRS-IS passcode of the base callsign; it is public knowledge, not a secret.
    public static func passcode(_ callsign: String) -> Int {
        let base = Array(normalize(callsign).prefix { $0 != "-" }.utf16)
        var hash = 0x73E2
        for index in stride(from: 0, to: base.count, by: 2) {
            hash ^= Int(base[index]) << 8
            if index + 1 < base.count {
                hash ^= Int(base[index + 1])
            }
        }
        return hash & 0x7FFF
    }

    /// `loginLine`: with receive on, a range filter around the location, or `m/` (around our last position).
    public static func loginLine(
        callsign: String,
        passcode: Int,
        software: String,
        version: String,
        receive: Bool,
        latitude: Double?,
        longitude: Double?,
        radiusKm: Double
    ) -> String {
        let login = "user \(callsign) pass \(passcode) vers \(software) \(version)"
        guard receive else { return login }
        guard let latitude, let longitude, latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude),
            (-180...180).contains(longitude)
        else { return login + " filter m/" + distance(radiusKm) }
        return login + " filter r/\(Java.format(latitude, decimals: 5))/\(Java.format(longitude, decimals: 5))/"
            + distance(radiusKm)
    }

    /// `formatFilterDistance`: three decimals without trailing zeros.
    static func distance(_ kilometres: Double) -> String {
        var text = Java.format(kilometres, decimals: 3)
        while text.hasSuffix("0") {
            text.removeLast()
        }
        return text.hasSuffix(".") ? String(text.dropLast()) : text
    }
}
