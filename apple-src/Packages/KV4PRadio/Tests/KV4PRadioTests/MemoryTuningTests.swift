import KV4PPersistence
import KV4PSimulator
import KV4PTestSupport
import Testing

@testable import KV4PProtocol
@testable import KV4PRadio

/// `RadioAudioService.tuneToMemory`, `getTxFreq` and `makeSafeHamFreq`.
@Suite("Memory tuning")
struct MemoryTuningTests {
    static let vhf: ClosedRange<Float> = 134...174

    @Test("makeSafeHamFreq: 1467 → 146.7, clamped, four decimals")
    func safeFrequency() {
        #expect(HamFrequency.safe("1467", in: Self.vhf) == 146.7)
        #expect(HamFrequency.safe(" 146.52 ", in: Self.vhf) == 146.52)
        #expect(HamFrequency.safe("200", in: Self.vhf) == 174)
        #expect(HamFrequency.safe("abc", in: Self.vhf) == nil)
        #expect(HamFrequency.safe("inf", in: Self.vhf) == nil)
        #expect(HamFrequency.safe(146.340_01, in: Self.vhf) == 146.34)
        #expect(HamFrequency.format(146.52) == "146.5200")
    }

    @Test(
        "TX frequency follows the offset",
        arguments: [
            (MemoryOffset.none, 600, Float(146.94)),
            (.down, 600, 146.34),
            (.up, 600, 147.54),
            (.up, 5000, 151.94),
            (.down, 20000, 134),
        ] as [(MemoryOffset, Int, Float)]
    )
    func txFrequency(offset: MemoryOffset, kHz: Int, expected: Float) {
        let memory = ChannelMemory(name: "R", frequency: 146.94, offset: offset, offsetKHz: kHz)
        #expect(memory.txFrequency(in: Self.vhf) == expected)
    }

    @Test("tuning to a memory sets RX, TX with offset, tones and the memory id")
    func tune() async throws {
        let clock = ManualClock()
        let transport = SimulatorTransport(simulator: RadioSimulator(scenario: .ble), clock: clock)
        let controller = RadioController(transport: transport, clock: clock)
        var snapshots = controller.snapshots.makeAsyncIterator()
        await #expect(throws: RadioError.notReady) {
            try await controller.tune(to: ChannelMemory(name: "A", frequency: 146.52))
        }
        await controller.connect()
        _ = try #require(await snapshots.next { $0.status == .ready && $0.isInSync })
        let memory = ChannelMemory(
            id: 7,
            name: "N0CALL",
            frequency: 146.94,
            offset: .down,
            txTone: "100.0",
            rxTone: "123"
        )
        try await controller.tune(to: memory)
        let tuned = try #require(await snapshots.next { $0.isInSync && $0.deviceState?.radio.memoryId == 7 })
        let radio = try #require(tuned.deviceState?.radio)
        #expect(radio.freqRx == 146.94)
        #expect(radio.freqTx == 146.34)
        #expect(radio.ctcssTx == CTCSS.index(of: "100.0"))
        #expect(radio.ctcssRx == CTCSS.index(of: "123"))
        #expect(tuned.desired.flags.contains(.txAllowed))
        try await controller.tune(to: ChannelMemory(id: 8, name: "Air", frequency: 180, txTone: "12"))
        let clamped = try #require(await snapshots.next { $0.isInSync && $0.deviceState?.radio.memoryId == 8 })
        #expect(clamped.deviceState?.radio.freqRx == 174)
        #expect(clamped.deviceState?.radio.ctcssTx == 0)
        #expect(!clamped.desired.flags.contains(.txAllowed))
    }
}
