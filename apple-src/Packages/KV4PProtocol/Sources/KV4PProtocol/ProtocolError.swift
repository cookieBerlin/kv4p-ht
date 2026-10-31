/// Errors raised while encoding or decoding protocol messages.
public enum ProtocolError: Error, Equatable, Sendable {
    /// A message has the wrong length.
    case invalidLength(expected: Int, actual: Int)
    /// `Version.rfModuleType` is neither SA818 VHF nor UHF.
    case unknownRFModuleType(UInt8)
    /// An AX.25 packet exceeds `KV4P.ax25MaxDataLength`.
    case payloadTooLong(maximum: Int, actual: Int)
}
