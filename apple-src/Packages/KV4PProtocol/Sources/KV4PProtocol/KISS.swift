/// KISS framing constants and helpers.
///
/// Source of truth: `microcontroller-src/kv4p_ht_esp32_wroom_32/protocol.h`.
/// Specification: `docs/apple/03-protocol-spec.md` §2.
public enum KISS {
    public static let fend: UInt8 = 0xC0
    public static let fesc: UInt8 = 0xDB
    public static let tfend: UInt8 = 0xDC
    public static let tfesc: UInt8 = 0xDD
}
