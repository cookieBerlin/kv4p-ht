import Testing

@testable import KV4PProtocol

/// The device-side encoder must produce frames the Android-verified `KISSParser` reads back unchanged.
@Suite("Device frame encoder")
struct DeviceFrameEncoderTests {
    static let state = DeviceState(
        radio: RadioState(sequence: 0xC0DB, flags: [.radioConfigValid, .squelched], freqTx: 146.52, freqRx: 146.52),
        radioModuleStatus: .found,
        mode: .rx,
        latestRssi: 0xC0
    )

    @Test("HELLO round-trips through the KISS parser")
    func hello() {
        let version = FirmwareVersion(
            version: 17,
            radioModuleStatus: .found,
            windowSize: 2048,
            moduleType: .sa818VHF,
            minRadioFreq: 134,
            maxRadioFreq: 174,
            features: [.esp32AFSK]
        )
        let hello = Hello(version: version, deviceState: Self.state)
        #expect(parse(DeviceFrameEncoder.hello(hello)) == [.command(.hello, payload: hello.encoded())])
    }

    @Test("DEVICE_STATE round-trips through the KISS parser")
    func deviceState() {
        #expect(
            parse(DeviceFrameEncoder.deviceState(Self.state)) == [.command(.deviceState, payload: Self.state.encoded())]
        )
    }

    @Test("WINDOW_UPDATE round-trips through the KISS parser")
    func windowUpdate() {
        let update = WindowUpdate(size: 0xDBC0)
        #expect(
            parse(DeviceFrameEncoder.windowUpdate(update)) == [.command(.windowUpdate, payload: update.encoded())]
        )
    }

    @Test("received AX.25 packets are sent as KISS DATA")
    func ax25() {
        #expect(parse(DeviceFrameEncoder.ax25([0xC0, 0xDB, 0x41])) == [.ax25([0xC0, 0xDB, 0x41])])
    }

    private func parse(_ bytes: [UInt8]) -> [ReceivedFrame] {
        var parser = KISSParser()
        return parser.process(bytes)
    }
}
