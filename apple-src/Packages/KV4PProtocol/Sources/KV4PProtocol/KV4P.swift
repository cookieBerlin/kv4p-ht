/// KV4P vendor protocol carried in KISS SETHARDWARE frames.
///
/// Specification: `docs/apple/03-protocol-spec.md` §3.
public enum KV4P {
    public static let protocolVersion: UInt8 = 0x01
    public static let vendorPrefix: [UInt8] = Array("KV4P".utf8)
    /// `"KV4P"` + version + command.
    public static let vendorHeaderLength = vendorPrefix.count + 2
    /// Maximum vendor command payload.
    public static let protoMTU = 2048
    /// APRS maximum AX.25 UI frame without FCS: ten addresses, control/PID, 256-byte information field.
    public static let ax25MaxDataLength = 10 * 7 + 2 + 256
    /// Maximum decoded KISS frame: command byte, vendor header and payload.
    public static let maxFrameSize = 1 + vendorHeaderLength + protoMTU
}

/// Commands sent by the host (`docs/apple/03-protocol-spec.md` §3.1).
public enum HostCommand: UInt8, Sendable {
    case txAudio = 0x0C
    case desiredState = 0x0D
    case txDigital = 0x0E
    case txAX25 = 0x0F
}

/// Commands sent by the device (`docs/apple/03-protocol-spec.md` §3.2).
public enum DeviceCommand: UInt8, Sendable {
    case debugInfo = 0x01
    case debugError = 0x02
    case debugWarn = 0x03
    case debugDebug = 0x04
    case debugTrace = 0x05
    case hello = 0x06
    case windowUpdate = 0x09
    case deviceState = 0x0B
    case rxAudio = 0x0C
    case rxDigital = 0x0E
}
