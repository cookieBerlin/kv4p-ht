/// A callsign with SSID, as an AX.25 address or path element (java-aprs `Callsign` and `Digipeater`).
public struct AX25Address: Equatable, Sendable, CustomStringConvertible {
    public var callsign: String
    /// Empty for SSID 0.
    public var ssid: String
    /// The digipeater repeated the packet (H bit, `*` in TNC2).
    public var isUsed: Bool

    /// `Digipeater(String)`: `N0CALL-9*`; `nil` where java-aprs throws (only `-` characters).
    public init?(_ text: String) {
        let parts = Java.split(text.replacing("*", with: ""), "-")
        guard let call = parts.first else { return nil }
        callsign = call.uppercased()
        ssid = parts.count > 1 ? parts[1] : ""
        isUsed = text.contains("*")
    }

    /// The source of a received packet as a path element.
    init(call: String) {
        let parts = call.split(separator: "-", maxSplits: 1).map(String.init)
        callsign = parts[0]
        ssid = parts.count > 1 ? parts[1] : ""
        isUsed = false
    }

    /// `Callsign(byte[], int)` and `Digipeater(byte[], int)`: seven address bytes.
    init(ax25 bytes: ArraySlice<UInt8>) {
        let start = bytes.startIndex
        callsign = Java.trim(Java.ascii(bytes[start..<start + 6].map { $0 >> 1 }))
        let ssidValue = Int(bytes[start + 6] & 0x1E) >> 1
        ssid = ssidValue == 0 ? "" : String(ssidValue)
        isUsed = bytes[start + 6] & 0x80 != 0
    }

    public var description: String {
        callsign + (ssid.isEmpty ? "" : "-" + ssid) + (isUsed ? "*" : "")
    }
}
