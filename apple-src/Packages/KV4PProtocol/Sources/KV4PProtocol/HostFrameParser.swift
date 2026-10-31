/// A frame received from the host, as dispatched by the firmware `KissParser`.
public enum HostFrame: Equatable, Sendable {
    /// KISS DATA: an AX.25 packet without FCS to transmit.
    case ax25([UInt8])
    case kissParameter(KISS.Parameter, value: UInt8)
    /// KV4P vendor command with its payload.
    case command(HostCommand, payload: [UInt8])
}

/// A host frame together with the flow-control credit it consumed.
public struct ParsedHostFrame: Equatable, Sendable {
    /// `nil` for frames the firmware ignores; those are still acknowledged.
    public let content: HostFrame?
    /// Encoded bytes the device acknowledges with `WINDOW_UPDATE`.
    public let encodedLength: Int
}

/// Incremental device-side parser for the host → device stream, used by the simulator.
///
/// Like the firmware, it acknowledges every complete frame, including ignored ones, but never empty or dropped
/// frames.
public struct HostFrameParser: Sendable {
    private var deframer = KISSDeframer()

    public init() {}

    public mutating func process(_ bytes: some Sequence<UInt8>) -> [ParsedHostFrame] {
        bytes.compactMap { byte in
            deframer.process(byte).map { ParsedHostFrame(content: Self.decode($0), encodedLength: $0.encodedLength) }
        }
    }

    private static func decode(_ frame: KISSDeframer.Frame) -> HostFrame? {
        let payload = frame.payload
        switch frame.command {
        case KISS.Command.data:
            return (1...KV4P.ax25MaxDataLength).contains(payload.count) ? .ax25(Array(payload)) : nil
        case KISS.Command.setHardware:
            guard let vendor = KV4P.vendorCommand(payload), let command = HostCommand(rawValue: vendor.command)
            else { return nil }
            return .command(command, payload: vendor.payload)
        default:
            guard let parameter = frame.command.flatMap(KISS.Parameter.init(rawValue:)), let value = payload.first,
                payload.count == 1
            else { return nil }
            return .kissParameter(parameter, value: value)
        }
    }
}
