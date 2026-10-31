/// A frame received from the device.
public enum ReceivedFrame: Equatable, Sendable {
    /// KISS DATA: an AX.25 packet without FCS.
    case ax25([UInt8])
    /// KV4P vendor command with its payload.
    case command(DeviceCommand, payload: [UInt8])
}

/// Incremental host-side parser for the device → host stream, matching the Android `Protocol.KissParser`.
public struct KISSParser: Sendable {
    private var deframer = KISSDeframer()

    public init() {}

    /// Feeds bytes from the transport; frames may span calls. Returns the frames completed by these bytes.
    public mutating func process(_ bytes: some Sequence<UInt8>) -> [ReceivedFrame] {
        bytes.compactMap { deframer.process($0).flatMap(Self.decode) }
    }

    /// The frame size limit already caps the command payload at `KV4P.protoMTU`.
    private static func decode(_ frame: KISSDeframer.Frame) -> ReceivedFrame? {
        switch frame.command {
        case KISS.Command.data:
            return (1...KV4P.ax25MaxDataLength).contains(frame.payload.count) ? .ax25(Array(frame.payload)) : nil
        case KISS.Command.setHardware:
            guard let vendor = KV4P.vendorCommand(frame.payload), let command = DeviceCommand(rawValue: vendor.command)
            else { return nil }
            return .command(command, payload: vendor.payload)
        default:
            return nil
        }
    }
}
