/// Encodes host → device frames, byte-identical to the Android `Protocol.Sender`.
public enum FrameEncoder {
    /// KISS DATA frame carrying an AX.25 packet without FCS.
    public static func ax25(_ packet: [UInt8]) throws(ProtocolError) -> [UInt8] {
        try requireAX25Length(packet)
        return KISS.frame(command: KISS.Command.data, payload: packet)
    }

    /// Transmits an AX.25 packet once on a temporary frequency; the device then restores its RX configuration.
    public static func ax25(
        _ packet: [UInt8],
        onFrequency freqTx: Float,
        bandwidth: UInt8,
        ctcssTx: UInt8
    ) throws(ProtocolError) -> [UInt8] {
        try requireAX25Length(packet)
        return vendor(.txAX25, TXChannel(freqTx: freqTx, bandwidth: bandwidth, ctcssTx: ctcssTx).encoded() + packet)
    }

    /// One IMA ADPCM block of TX audio.
    public static func txAudio(_ block: some Collection<UInt8>) -> [UInt8] {
        vendor(.txAudio, block)
    }

    /// One Codec2 frame in FreeDV 2400B mode.
    public static func txDigital(_ frame: some Collection<UInt8>) -> [UInt8] {
        vendor(.txDigital, frame)
    }

    /// KISS TXDELAY in units of 10 ms.
    public static func kissTxDelay(_ value: UInt8) -> [UInt8] {
        KISS.frame(command: KISS.Command.txDelay, payload: [value])
    }

    public static func desiredState(_ state: HostDesiredState) -> [UInt8] {
        vendor(.desiredState, state.encoded())
    }

    /// Vendor payloads longer than `KV4P.protoMTU` are truncated, as in the Android sender.
    static func vendor(_ command: HostCommand, _ payload: some Collection<UInt8>) -> [UInt8] {
        KV4P.vendorFrame(command.rawValue, payload.prefix(KV4P.protoMTU))
    }

    private static func requireAX25Length(_ packet: [UInt8]) throws(ProtocolError) {
        guard packet.count <= KV4P.ax25MaxDataLength else {
            throw .payloadTooLong(maximum: KV4P.ax25MaxDataLength, actual: packet.count)
        }
    }
}
