import KV4PSimulator
import KV4PTestSupport
import Testing

@testable import KV4PProtocol
@testable import KV4PRadio

/// `RadioAudioService.txAX25PacketOnFrequency`: one packet on a frequency, with the current bandwidth and tone.
@Suite("AX.25 transmit")
struct AX25TransmitTests {
    static let frame: [UInt8] = [
        0x82, 0xA0, 0xA4, 0xA6, 0x40, 0x40, 0xE0, 0x9C, 0x60, 0x86, 0x82, 0x98, 0x98, 0x61, 0x03, 0xF0, 0x3E,
    ]

    struct Setup {
        let clock = ManualClock()
        let microphone = FakeMicrophone()
        let transport: SimulatorTransport<ManualClock>
        let controller: RadioController<ManualClock>
        var snapshots: AsyncStream<RadioSnapshot>.Iterator

        init() {
            transport = SimulatorTransport(simulator: RadioSimulator(scenario: .ble), clock: clock)
            controller = RadioController(transport: transport, clock: clock, microphone: microphone)
            snapshots = controller.snapshots.makeAsyncIterator()
        }

        mutating func ready() async throws {
            await controller.connect()
            _ = try #require(await snapshots.next { $0.status == .ready && $0.isInSync })
            await controller.update { $0.setTxTone(5) }
            try await controller.tune(rx: 146.52, tx: 146.52)
        }
    }

    @Test("the packet is sent on the given frequency with the current bandwidth and TX tone")
    func transmits() async throws {
        var setup = Setup()
        try await setup.ready()
        try await setup.controller.transmitAX25(Self.frame, frequency: 144.8)
        #expect(
            await eventually {
                let sent = await setup.transport.simulator.transmittedPackets
                return sent.map(\.packet) == [Self.frame]
                    && sent.first?.channel == TXChannel(freqTx: 144.8, bandwidth: 1, ctcssTx: 5)
            }
        )
    }

    @Test("not outside the ham band, not while transmitting or scanning, not before HELLO, not oversized")
    func refused() async throws {
        var setup = Setup()
        await #expect(throws: RadioError.notReady) {
            try await setup.controller.transmitAX25(Self.frame, frequency: 144.8)
        }
        try await setup.ready()
        await #expect(throws: RadioError.transmitNotAllowed) {
            try await setup.controller.transmitAX25(Self.frame, frequency: 150)
        }
        await #expect(throws: RadioError.invalidPacket) {
            try await setup.controller.transmitAX25([UInt8](repeating: 0x41, count: 400), frequency: 144.8)
        }
        try await setup.controller.startTransmitting()
        await #expect(throws: RadioError.busy) { try await setup.controller.transmitAX25(Self.frame, frequency: 144.8) }
        await setup.controller.stopTransmitting()
        try await setup.controller.startScan([])
        await #expect(throws: RadioError.busy) { try await setup.controller.transmitAX25(Self.frame, frequency: 144.8) }
    }
}
