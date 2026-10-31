/// Channel for a single AX.25 transmission on another frequency (`Ax25TxOverride`, 6 bytes), the header of
/// `HOST_TX_AX25`.
public struct TXChannel: Equatable, Sendable {
    public static let byteCount = 6

    /// MHz.
    public var freqTx: Float
    /// `0x00` = 12.5 kHz, `0x01` = 25 kHz.
    public var bandwidth: UInt8
    /// SA818 tone index, 0 = none.
    public var ctcssTx: UInt8

    public init(freqTx: Float, bandwidth: UInt8, ctcssTx: UInt8) {
        self.freqTx = freqTx
        self.bandwidth = bandwidth
        self.ctcssTx = ctcssTx
    }

    public init(decoding bytes: [UInt8]) throws(ProtocolError) {
        try bytes.requireCount(Self.byteCount)
        var reader = ByteReader(bytes)
        freqTx = reader.float()
        bandwidth = reader.uint8()
        ctcssTx = reader.uint8()
    }

    public func encoded() -> [UInt8] {
        var writer = ByteWriter()
        writer.float(freqTx)
        writer.uint8(bandwidth)
        writer.uint8(ctcssTx)
        return writer.bytes
    }
}
