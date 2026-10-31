/// A frame received from the device.
public enum ReceivedFrame: Equatable, Sendable {
    /// KISS DATA: an AX.25 packet without FCS.
    case ax25([UInt8])
    /// KV4P vendor command with its payload.
    case command(DeviceCommand, payload: [UInt8])
}

/// Incremental KISS stream parser with the same rules as the firmware and the Android `Protocol.KissParser`
/// (`docs/apple/03-protocol-spec.md` §2).
public struct KISSParser: Sendable {
    private var frame: [UInt8] = []
    private var inFrame = false
    private var escaping = false
    private var dropping = false

    public init() {}

    /// Feeds bytes from the transport; frames may span calls. Returns the frames completed by these bytes.
    public mutating func process(_ bytes: some Sequence<UInt8>) -> [ReceivedFrame] {
        var frames: [ReceivedFrame] = []
        for byte in bytes {
            if let received = process(byte) {
                frames.append(received)
            }
        }
        return frames
    }

    private mutating func process(_ byte: UInt8) -> ReceivedFrame? {
        if byte == KISS.fend {
            let received = dropping || frame.isEmpty ? nil : Self.decode(frame)
            frame.removeAll(keepingCapacity: true)
            inFrame = true
            escaping = false
            dropping = false
            return received
        }
        guard inFrame, !dropping else { return nil }
        if escaping {
            escaping = false
            switch byte {
            case KISS.tfend: append(KISS.fend)
            case KISS.tfesc: append(KISS.fesc)
            default: dropping = true  // unknown escape: drop until the next FEND
            }
        } else if byte == KISS.fesc {
            escaping = true
        } else {
            append(byte)
        }
        return nil
    }

    private mutating func append(_ byte: UInt8) {
        guard frame.count < KV4P.maxFrameSize else {
            dropping = true
            return
        }
        frame.append(byte)
    }

    private static func decode(_ frame: [UInt8]) -> ReceivedFrame? {
        let commandByte = frame[0]
        let payload = Array(frame.dropFirst())
        guard commandByte >> 4 == 0 else { return nil }  // only port 0
        switch commandByte & 0x0F {
        case KISS.Command.data:
            return (1...KV4P.ax25MaxDataLength).contains(payload.count) ? .ax25(payload) : nil
        case KISS.Command.setHardware:
            return decodeVendor(payload)
        default:
            return nil
        }
    }

    /// The frame size limit already caps the command payload at `KV4P.protoMTU`.
    private static func decodeVendor(_ payload: [UInt8]) -> ReceivedFrame? {
        guard payload.count >= KV4P.vendorHeaderLength,
            payload.starts(with: KV4P.vendorPrefix),
            payload[KV4P.vendorPrefix.count] == KV4P.protocolVersion,
            let command = DeviceCommand(rawValue: payload[KV4P.vendorPrefix.count + 1])
        else { return nil }
        return .command(command, payload: Array(payload.dropFirst(KV4P.vendorHeaderLength)))
    }
}
