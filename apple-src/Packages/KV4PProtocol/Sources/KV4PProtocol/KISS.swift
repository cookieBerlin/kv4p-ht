/// KISS framing constants and helpers.
///
/// Source of truth: `microcontroller-src/kv4p_ht_esp32_wroom_32/protocol.h`.
/// Specification: `docs/apple/03-protocol-spec.md` §2.
public enum KISS {
    public static let fend: UInt8 = 0xC0
    public static let fesc: UInt8 = 0xDB
    public static let tfend: UInt8 = 0xDC
    public static let tfesc: UInt8 = 0xDD

    /// Escapes `FEND` and `FESC` inside a frame payload.
    public static func escape(_ bytes: [UInt8]) -> [UInt8] {
        var escaped: [UInt8] = []
        escaped.reserveCapacity(bytes.count)
        for byte in bytes {
            switch byte {
            case fend: escaped += [fesc, tfend]
            case fesc: escaped += [fesc, tfesc]
            default: escaped.append(byte)
            }
        }
        return escaped
    }
}
