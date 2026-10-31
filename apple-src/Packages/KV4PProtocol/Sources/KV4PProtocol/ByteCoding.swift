/// Little-endian reader over a byte array whose length the caller has checked.
struct ByteReader {
    private let bytes: [UInt8]
    private var offset = 0

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    mutating func uint8() -> UInt8 {
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func uint16() -> UInt16 {
        UInt16(uint8()) | UInt16(uint8()) << 8
    }

    mutating func uint32() -> UInt32 {
        UInt32(uint16()) | UInt32(uint16()) << 16
    }

    mutating func float() -> Float {
        Float(bitPattern: uint32())
    }
}

/// Little-endian writer.
struct ByteWriter {
    private(set) var bytes: [UInt8] = []

    mutating func uint8(_ value: UInt8) {
        bytes.append(value)
    }

    mutating func uint16(_ value: UInt16) {
        bytes += [UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8)]
    }

    mutating func uint32(_ value: UInt32) {
        uint16(UInt16(truncatingIfNeeded: value))
        uint16(UInt16(truncatingIfNeeded: value >> 16))
    }

    mutating func float(_ value: Float) {
        uint32(value.bitPattern)
    }

    mutating func bytes(_ value: some Sequence<UInt8>) {
        bytes += value
    }
}

extension Array where Element == UInt8 {
    /// Throws unless the array has exactly `count` bytes.
    func requireCount(_ count: Int) throws(ProtocolError) {
        guard self.count == count else { throw .invalidLength(expected: count, actual: self.count) }
    }
}
