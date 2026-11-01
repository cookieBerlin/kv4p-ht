import KV4PSimulator
import KV4PTestSupport
import KV4PTransport
import Testing

@testable import KV4PProtocol
@testable import KV4PRadio

/// `RadioController` end to end against the simulator (ADR-0014 A).
@Suite("Radio controller")
struct RadioControllerTests {
    struct Setup {
        let clock = ManualClock()
        let transport: SimulatorTransport<ManualClock>
        let controller: RadioController<ManualClock>
        var snapshots: AsyncStream<RadioSnapshot>.Iterator

        init(_ scenario: Scenario = .ble) {
            transport = SimulatorTransport(simulator: RadioSimulator(scenario: scenario), clock: clock)
            controller = RadioController(transport: transport, clock: clock)
            snapshots = controller.snapshots.makeAsyncIterator()
        }

        /// Connects and waits until the radio is ready and the device confirmed the desired state.
        mutating func ready() async throws -> RadioSnapshot {
            await controller.connect()
            return try #require(await snapshots.next { $0.status == .ready && $0.isInSync })
        }
    }

    @Test("the controller runs on the continuous clock by default, with FreeDV available")
    func continuousClock() async throws {
        let controller = RadioController(transport: SimulatorTransport(simulator: RadioSimulator(scenario: .freeDV)))
        var snapshots = controller.snapshots.makeAsyncIterator()
        await controller.connect()
        _ = try #require(await snapshots.next { $0.status == .ready })
        await controller.setFreeDV(true)
        #expect(await controller.snapshot.isFreeDV)
        await controller.disconnect()
    }

    @Test("connect: HELLO is checked, the state seeded, audio and status reports opened")
    func connect() async throws {
        var setup = Setup()
        let snapshot = try await setup.ready()
        #expect(snapshot.firmware?.version == 17)
        #expect(snapshot.firmware?.windowSize == 4096)
        #expect(snapshot.deviceState?.radio.freqRx == 144)
        #expect(snapshot.deviceState?.mode == .rx)
        #expect(snapshot.desired.flags.isSuperset(of: [.rxAudioOpen, .enableStatusReports]))
        #expect(snapshot.sMeter == 0)
        #expect(await setup.transport.simulator.deviceState.radio.sequence == snapshot.desired.sequence)
    }

    @Test("tuning reaches the device")
    func tune() async throws {
        var setup = Setup()
        _ = try await setup.ready()
        try await setup.controller.tune(rx: 146.52, tx: 146.52, memoryId: 7)
        let tuned = try #require(
            await setup.snapshots.next { $0.isInSync && $0.deviceState?.radio.freqRx == 146.52 }
        )
        #expect(tuned.deviceState?.radio.memoryId == 7)
        await setup.controller.update { $0.setSquelch(5) }
        _ = try #require(await setup.snapshots.next { $0.isInSync && $0.deviceState?.radio.squelch == 5 })
    }

    @Test("frequencies outside the module range are rejected")
    func outOfRange() async throws {
        var setup = Setup()
        _ = try await setup.ready()
        await #expect(throws: RadioError.frequencyOutOfRange(433.5)) {
            try await setup.controller.tune(rx: 433.5, tx: 433.5)
        }
        await #expect(throws: RadioError.frequencyOutOfRange(180)) {
            try await setup.controller.tune(rx: 146.52, tx: 180)
        }
    }

    @Test("tuning needs a HELLO")
    func tuneBeforeHello() async {
        let setup = Setup()
        await #expect(throws: RadioError.notReady) { try await setup.controller.tune(rx: 146.52, tx: 146.52) }
        #expect(await setup.controller.snapshot.sMeter == 0)
    }

    @Test("old firmware is refused")
    func firmwareTooOld() async throws {
        var scenario = Scenario.ble
        scenario.firmwareVersion = 16
        var setup = Setup(scenario)
        await setup.controller.connect()
        #expect(await setup.snapshots.next { $0.status == .failed(.firmwareTooOld(16)) } != nil)
    }

    /// Any radio configuration would stall the firmware (protocol spec §9).
    @Test("without a radio module nothing is sent")
    func radioModuleNotFound() async throws {
        var setup = Setup(.noRadioModule)
        await setup.controller.connect()
        #expect(await setup.snapshots.next { $0.status == .failed(.radioModuleNotFound) } != nil)
        #expect(await !setup.transport.simulator.isStalled)
        #expect(await setup.transport.simulator.deviceState.radio.sequence == 0)
    }

    @Test("a device without HELLO times out")
    func helloTimeout() async throws {
        var scenario = Scenario.ble
        scenario.faults.omitsHello = true
        var setup = Setup(scenario)
        await setup.controller.connect()
        _ = await setup.snapshots.next { $0.status == .waitingForHello }
        await setup.clock.waitForSleepers(2)
        setup.clock.advance(by: RadioController<ManualClock>.defaultHelloTimeout)
        #expect(await setup.snapshots.next { $0.status == .failed(.helloTimeout) } != nil)
    }

    @Test("a HELLO that arrives while connect is still running is kept")
    func helloDuringConnect() async throws {
        var simulator = RadioSimulator(scenario: .ble)
        let hello = simulator.connect(at: .zero)
        let controller = Box<RadioController<ManualClock>>()
        let transport = ScriptedTransport { streams in
            streams.deliver(hello)
            while await controller.value?.snapshot.status != .ready {
                await Task.yield()
            }
        }
        controller.value = RadioController(transport: transport, clock: ManualClock())
        await controller.value?.connect()
        #expect(await controller.value?.snapshot.status == .ready)
    }

    @Test("an invalid HELLO is refused")
    func invalidHello() async throws {
        let transport = ScriptedTransport()
        let controller = RadioController(transport: transport, clock: ManualClock())
        var snapshots = controller.snapshots.makeAsyncIterator()
        await controller.connect()
        transport.streams.deliver(FrameEncoder.vendor(.desiredState, [1, 2, 3]))  // ignored host command byte
        transport.streams.deliver(DeviceFrameEncoder.windowUpdate(WindowUpdate(size: 10)))
        transport.streams.deliver(DeviceFrameEncoder.ax25([0x41]))  // handled by a later milestone
        transport.streams.deliver(KV4PProtocol.KV4P.vendorFrame(DeviceCommand.hello.rawValue, [17, 0]))
        #expect(await snapshots.next { $0.status == .failed(.invalidHello) } != nil)
        #expect(transport.sent.isEmpty)
    }

    @Test("a failing transport is reported")
    func connectFails() async {
        let controller = RadioController(
            transport: ScriptedTransport(connectError: .serviceNotFound),
            clock: ManualClock()
        )
        var snapshots = controller.snapshots.makeAsyncIterator()
        await controller.connect()
        #expect(await snapshots.next { $0.status == .failed(.transport(.serviceNotFound)) } != nil)
    }

    @Test("a lost connection is reported and disconnect returns to disconnected")
    func connectionLost() async throws {
        let transport = ScriptedTransport()
        let controller = RadioController(transport: transport, clock: ManualClock())
        var snapshots = controller.snapshots.makeAsyncIterator()
        await controller.connect()
        _ = await snapshots.next { $0.status == .waitingForHello }
        transport.streams.publish(.failed(.connectionLost))
        #expect(await snapshots.next { $0.status == .failed(.transport(.connectionLost)) } != nil)
        await controller.disconnect()
        #expect(await snapshots.next { $0.status == .disconnected } != nil)
    }

    @Test("disconnect detaches and a reconnect handshakes again")
    func reconnect() async throws {
        var setup = Setup()
        _ = try await setup.ready()
        await setup.controller.disconnect()
        let disconnected = try #require(await setup.snapshots.next { $0.status == .disconnected })
        #expect(disconnected.firmware == nil)
        _ = try await setup.ready()
    }
}

@Suite("Radio controller lifetime")
struct RadioControllerLifetimeTests {
    @Test("a released controller finishes its snapshots")
    func released() async {
        var controller: RadioController? = RadioController(transport: ScriptedTransport())
        let snapshots = controller?.snapshots
        await controller?.connect()
        controller = nil
        var count = 0
        for await _ in snapshots ?? AsyncStream { $0.finish() } {
            count += 1
        }
        #expect(count >= 2)
    }
}

/// Lets a transport closure reach the controller created after it.
final class Box<Value: Sendable>: @unchecked Sendable {
    var value: Value?
}
