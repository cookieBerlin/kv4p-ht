import KV4PPersistence
import KV4PSimulator
import KV4PTestSupport
import Testing

@testable import KV4PProtocol
@testable import KV4PRadio

/// `RadioAudioService.setScanning`, `nextScan` and `checkScanDueToSquelch`.
@Suite("Scan")
struct ScanTests {
    static let memories = [
        ChannelMemory(id: 1, name: "One", frequency: 146.52),
        ChannelMemory(id: 2, name: "Two", frequency: 145.5),
        ChannelMemory(id: 3, name: "Skipped", frequency: 147.0, skipDuringScan: true),
        ChannelMemory(id: 4, name: "Airband", frequency: 120),
        ChannelMemory(id: 5, name: "Five", frequency: 144.8),
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
        }

        /// Waits until the radio confirmed memory `id`.
        mutating func tuned(to id: Int32) async throws -> RadioSnapshot {
            try #require(await snapshots.next { $0.isInSync && $0.deviceState?.radio.memoryId == id })
        }

        /// Lets the squelch stay closed for the advance delay.
        func waitForAdvance() async {
            await clock.waitForSleepers(2)  // simulator ticker and scan timer
            clock.advance(by: RadioController<ManualClock>.scanAdvanceDelay)
        }
    }

    @Test("scans the memories in order while the squelch stays closed, with squelch 7")
    func scans() async throws {
        var setup = Setup()
        try await setup.ready()
        try await setup.controller.startScan(Self.memories)
        let first = try await setup.tuned(to: 1)
        #expect(first.isScanning)
        #expect(first.deviceState?.radio.squelch == 7)
        await setup.waitForAdvance()
        _ = try await setup.tuned(to: 2)
        await setup.waitForAdvance()
        _ = try await setup.tuned(to: 5)  // skipped and out of range
        await setup.waitForAdvance()
        _ = try await setup.tuned(to: 1)
    }

    @Test("a signal holds the scan; stopping restores the squelch")
    func signalHolds() async throws {
        var setup = Setup()
        try await setup.ready()
        await setup.controller.update { $0.setSquelch(3) }
        try await setup.controller.startScan(Self.memories)
        let first = try await setup.tuned(to: 1)
        #expect(first.deviceState?.radio.squelch == 3)
        await setup.transport.setCarrier(Carrier())
        _ = try #require(
            await setup.snapshots.next { $0.deviceState?.radio.flags.contains(.squelched) == false }
        )
        await setup.clock.waitForSleepers(1)
        setup.clock.advance(by: .seconds(1))
        await setup.controller.stopScan()
        let stopped = try #require(await setup.snapshots.next { !$0.isScanning && $0.isInSync })
        #expect(stopped.deviceState?.radio.memoryId == 1)
        #expect(await setup.transport.simulator.deviceState.radio.memoryId == 1)
    }

    @Test("other reports while waiting do not restart the delay")
    func reportsWhileWaiting() async throws {
        var setup = Setup()
        try await setup.ready()
        try await setup.controller.startScan(Self.memories)
        _ = try await setup.tuned(to: 1)
        await setup.clock.waitForSleepers(2)
        await setup.controller.update { $0.setHighPower(false) }
        _ = try #require(
            await setup.snapshots.next { $0.isInSync && $0.deviceState?.radio.flags.contains(.highPower) == false }
        )
        setup.clock.advance(by: RadioController<ManualClock>.scanAdvanceDelay)
        _ = try await setup.tuned(to: 2)
    }

    @Test("after a signal ends, the scan moves on again")
    func signalEnds() async throws {
        var setup = Setup()
        try await setup.ready()
        try await setup.controller.startScan(Self.memories)
        _ = try await setup.tuned(to: 1)
        await setup.transport.setCarrier(Carrier())
        _ = try #require(await setup.snapshots.next { $0.deviceState?.radio.flags.contains(.squelched) == false })
        await setup.clock.waitForSleepers(1)
        setup.clock.advance(by: .seconds(1))  // the squelch is open: no advance
        await setup.transport.setCarrier(nil)
        _ = try #require(await setup.snapshots.next { $0.deviceState?.radio.flags.contains(.squelched) == true })
        await setup.waitForAdvance()
        _ = try await setup.tuned(to: 2)
    }

    @Test("stopping a scan from squelch 0 restores squelch 0 on the active memory")
    func stopRestores() async throws {
        var setup = Setup()
        try await setup.ready()
        try await setup.controller.startScan(Self.memories)
        _ = try await setup.tuned(to: 1)
        await setup.controller.stopScan()
        let stopped = try #require(
            await setup.snapshots.next { !$0.isScanning && $0.isInSync && $0.deviceState?.radio.squelch == 0 }
        )
        #expect(stopped.deviceState?.radio.memoryId == 1)
        await setup.controller.stopScan()
    }

    @Test("nothing to scan: no memory is eligible or the list is empty")
    func nothingToScan() async throws {
        var setup = Setup()
        try await setup.ready()
        try await setup.controller.startScan([])
        try await setup.controller.startScan([Self.memories[2], Self.memories[3]])
        #expect(await setup.controller.snapshot.isScanning)
        #expect(await setup.controller.snapshot.desired.memoryId == -1)
    }

    @Test("scan needs a ready radio; PTT and disconnect end it")
    func endsScan() async throws {
        var setup = Setup()
        await #expect(throws: RadioError.notReady) { try await setup.controller.startScan(Self.memories) }
        try await setup.ready()
        try await setup.controller.startScan(Self.memories)
        _ = try await setup.tuned(to: 1)
        try await setup.controller.startTransmitting()
        #expect(await !setup.controller.snapshot.isScanning)
        await setup.controller.stopTransmitting()
        try await setup.controller.startScan(Self.memories)
        await setup.controller.disconnect()
        #expect(await !setup.controller.snapshot.isScanning)
    }

    @Test("a manual tune ends the scan")
    func manualTune() async throws {
        var setup = Setup()
        try await setup.ready()
        try await setup.controller.startScan(Self.memories)
        try await setup.controller.tune(rx: 146.52, tx: 146.52)
        #expect(await !setup.controller.snapshot.isScanning)
        try await setup.controller.startScan(Self.memories)
        try await setup.controller.tune(to: Self.memories[1])
        #expect(await !setup.controller.snapshot.isScanning)
    }
}
