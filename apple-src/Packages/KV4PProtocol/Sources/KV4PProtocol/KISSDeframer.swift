/// Byte-level KISS deframing shared by both directions, with the same rules as the firmware and the Android
/// `Protocol.KissParser` (`docs/apple/03-protocol-spec.md` §2).
struct KISSDeframer: Sendable {
    /// A complete, unescaped frame.
    struct Frame: Equatable, Sendable {
        let bytes: [UInt8]
        /// Encoded bytes from the opening to the closing FEND, both included, as counted by the firmware.
        let encodedLength: Int

        /// The KISS command, or `nil` for a port other than 0.
        var command: UInt8? { bytes[0] >> 4 == 0 ? bytes[0] & 0x0F : nil }

        var payload: ArraySlice<UInt8> { bytes.dropFirst() }
    }

    private var frame: [UInt8] = []
    private var encodedCount = 0
    private var inFrame = false
    private var escaping = false
    private var dropping = false

    /// Returns the frame completed by `byte`. Empty and dropped frames are not returned.
    mutating func process(_ byte: UInt8) -> Frame? {
        if byte == KISS.fend {
            let completed = dropping || frame.isEmpty ? nil : Frame(bytes: frame, encodedLength: encodedCount + 2)
            frame.removeAll(keepingCapacity: true)
            encodedCount = 0
            inFrame = true
            escaping = false
            dropping = false
            return completed
        }
        guard inFrame else { return nil }
        encodedCount += 1
        guard !dropping else { return nil }
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
}
