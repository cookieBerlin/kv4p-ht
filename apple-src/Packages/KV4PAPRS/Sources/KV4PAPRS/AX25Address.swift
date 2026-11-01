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

    /// A callsign of a packet (source or destination), split like `Callsign(String)`.
    init(call: String) {
        let parts = call.split(separator: "-", omittingEmptySubsequences: false)
        callsign = parts[0].uppercased()
        ssid = parts.count > 1 ? String(parts[1]) : ""
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

    func used() -> AX25Address {
        var address = self
        address.isUsed = true
        return address
    }

    /// `Digipeater.toAX25`: callsign shifted left and padded, SSID byte `u11ssss0` with the used flag.
    func ax25Bytes() throws(APRSEncodeError) -> [UInt8] {
        let call = Java.asciiBytes(callsign)
        guard call.count <= 6 else { throw .callsignTooLong }
        let ssidValue = Java.parseInt(ssid) ?? 0
        return call.map { $0 << 1 } + [UInt8](repeating: 0x40, count: 6 - call.count)
            + [UInt8(truncatingIfNeeded: 0x60 | ((ssidValue * 2) & 0x1E)) | (isUsed ? 0x80 : 0)]
    }
}

/// A packet that cannot be sent as AX.25.
public enum APRSEncodeError: Error, Equatable, Sendable {
    /// More than six characters before the SSID.
    case callsignTooLong
}
