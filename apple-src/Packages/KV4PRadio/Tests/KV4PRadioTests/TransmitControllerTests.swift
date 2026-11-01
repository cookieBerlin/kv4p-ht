import KV4PAudio
import KV4PSimulator
import KV4PTestSupport
import Synchronization
import Testing

@testable import KV4PProtocol
@testable import KV4PRadio

/// A microphone the test speaks into.
final class FakeMicrophone: AudioInput {
    struct Failure: Error {}

    private struct State {
        var continuation: AsyncStream<[Int16]>.Continuation?
        var starts = 0
        var stops = 0
    }

    private let state = Mutex(State())
    private let fails: Bool
    /// With `holdsStart`, `start()` returns only after `release()`.
    private let gate: AsyncStream<Void>?
    private let opener: AsyncStream<Void>.Continuation?

    init(fails: Bool = false, holdsStart: Bool = false) {
        self.fails = fails
        if holdsStart {
            let (gate, opener) = AsyncStream.makeStream(of: Void.self)
            self.gate = gate
            self.opener = opener
        } else {
            gate = nil
            opener = nil
        }
    }

    func release() {
        opener?.finish()
    }

    var starts: Int { state.withLock { $0.starts } }
    var stops: Int { state.withLock { $0.stops } }

    func start() async throws -> AsyncStream<[Int16]> {
        state.withLock { $0.starts += 1 }
        for await _ in gate ?? AsyncStream { $0.finish() } {}
        if fails { throw Failure() }
        let (stream, continuation) = AsyncStream.makeStream(of: [Int16].self)
        state.withLock { $0.continuation = continuation }
        return stream
    }

    func stop() {
        state.withLock {
            $0.stops += 1
            $0.continuation?.finish()
            $0.continuation = nil
        }
    }

    func speak(_ samples: [Int16]) {
        _ = state.withLock { $0.continuation?.yield(samples) }
    }
}

/// PTT, TX audio and the TX rules of `RadioAudioService` (`startPtt`, `endPtt`, `updateTxAllowed`).
@Suite("Radio controller transmit")
struct TransmitControllerTests {
    static let speech = (0..<(3 * KV4P.audioBlockSamples)).map { Int16(truncatingIfNeeded: $0 * 211) }

    /// Against the simulator.
    struct Simulated {
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

        /// Ready and tuned to 146.52 MHz, where TX is allowed.
        mutating func tuned() async throws {
            await controller.connect()
            _ = try #require(await snapshots.next { $0.status == .ready && $0.isInSync })
            try await controller.tune(rx: 146.52, tx: 146.52)
            _ = try #require(
                await snapshots.next {
                    $0.isInSync && $0.deviceState?.radio.freqTx == 146.52 && $0.desired.flags.contains(.txAllowed)
                }
            )
        }
    }

    /// Against a scripted transport: the device only says HELLO, the test sends the rest.
    struct Scripted {
        let clock = ManualClock()
        let transport = ScriptedTransport()
        let controller: RadioController<ManualClock>
        var snapshots: AsyncStream<RadioSnapshot>.Iterator
        var simulator = RadioSimulator(scenario: .ble)

        init(microphone: FakeMicrophone, rxAudio: RecordingSink? = nil) {
            controller = RadioController(transport: transport, clock: clock, rxAudio: rxAudio, microphone: microphone)
            snapshots = controller.snapshots.makeAsyncIterator()
        }

        /// Ready and tuned to 146.52 MHz, where TX is allowed.
        mutating func ready() async throws {
            await controller.connect()
            transport.streams.deliver(simulator.connect(at: .zero))
            _ = try #require(await snapshots.next { $0.status == .ready })
            try await controller.tune(rx: 146.52, tx: 146.52)
        }
    }

    @Test("PTT keys the radio and streams the microphone with its gain")
    func transmit() async throws {
        var setup = Simulated()
        try await setup.tuned()
        await setup.controller.setMicGain(.med)
        try await setup.controller.startTransmitting()
        #expect(await setup.controller.snapshot.isTransmitting)
        #expect(await eventually { await setup.transport.simulator.deviceState.mode == .tx })
        setup.microphone.speak(Array(Self.speech[..<100]))
        setup.microphone.speak(Array(Self.speech[100...]))
        #expect(await eventually { await setup.transport.simulator.transmittedAudioBlocks == 3 })
        var encoder = TXAudioEncoder(gain: .med)
        #expect(await setup.transport.simulator.lastTransmittedAudio == encoder.encode(Self.speech).last)
        await setup.controller.stopTransmitting()
        #expect(setup.microphone.stops == 1)
        #expect(await eventually { await setup.transport.simulator.deviceState.mode == .rx })
        #expect(await !setup.controller.snapshot.isTransmitting)
    }

    @Test("outside the ham band TX is not allowed")
    func outsideBand() async throws {
        var setup = Simulated()
        await setup.controller.connect()
        // 144.000 MHz: a 25 kHz channel reaches below the 2 m band.
        _ = try #require(
            await setup.snapshots.next { $0.isInSync && $0.status == .ready && !$0.desired.flags.contains(.txAllowed) }
        )
        await #expect(throws: RadioError.transmitNotAllowed) { try await setup.controller.startTransmitting() }
        #expect(setup.microphone.starts == 0)
        try await setup.controller.tune(rx: 146.52, tx: 150)
        #expect(await !setup.controller.snapshot.desired.flags.contains(.txAllowed))
    }

    @Test("narrower TX limits forbid TX and AX.25 above them, also on the tuned frequency")
    func limits() async throws {
        var setup = Simulated()
        try await setup.tuned()
        try await setup.controller.tune(rx: 147, tx: 147)
        _ = try #require(await setup.snapshots.next { $0.isInSync && $0.desired.flags.contains(.txAllowed) })
        var limits = TXLimits()
        limits.max2m = 146
        await RadioController(transport: ScriptedTransport(), clock: ManualClock()).setTXLimits(limits)  // no radio yet
        await setup.controller.setTXLimits(limits)
        #expect(await !setup.controller.snapshot.desired.flags.contains(.txAllowed))
        await #expect(throws: RadioError.transmitNotAllowed) {
            try await setup.controller.transmitAX25([0x01], frequency: 147)
        }
        try await setup.controller.tune(rx: 145, tx: 145)
        #expect(await setup.controller.snapshot.desired.flags.contains(.txAllowed))
    }

    @Test("TX needs a ready radio and a microphone")
    func preconditions() async throws {
        let microphone = FakeMicrophone()
        let setup = Scripted(microphone: microphone)
        await #expect(throws: RadioError.notReady) { try await setup.controller.startTransmitting() }
        let withoutMicrophone = RadioController(transport: ScriptedTransport(), clock: ManualClock())
        await #expect(throws: RadioError.notReady) { try await withoutMicrophone.startTransmitting() }
        #expect(microphone.starts == 0)
    }

    @Test("a microphone that cannot start keeps the radio in RX")
    func microphoneFails() async throws {
        var setup = Scripted(microphone: FakeMicrophone(fails: true))
        try await setup.ready()
        await #expect(throws: RadioError.microphoneUnavailable) { try await setup.controller.startTransmitting() }
        #expect(await !setup.controller.snapshot.isTransmitting)
    }

    @Test("without a microphone TX is unavailable")
    func noMicrophone() async throws {
        let transport = ScriptedTransport()
        let controller = RadioController(transport: transport, clock: ManualClock())
        var snapshots = controller.snapshots.makeAsyncIterator()
        await controller.connect()
        var simulator = RadioSimulator(scenario: .ble)
        transport.streams.deliver(simulator.connect(at: .zero))
        _ = await snapshots.next { $0.status == .ready }
        try await controller.tune(rx: 146.52, tx: 146.52)
        await #expect(throws: RadioError.microphoneUnavailable) { try await controller.startTransmitting() }
    }

    @Test("a second PTT press while transmitting is ignored")
    func doublePress() async throws {
        let microphone = FakeMicrophone()
        var setup = Scripted(microphone: microphone)
        try await setup.ready()
        try await setup.controller.startTransmitting()
        try await setup.controller.startTransmitting()
        #expect(microphone.starts == 1)
        await setup.controller.stopTransmitting()
        await setup.controller.stopTransmitting()
        #expect(microphone.stops == 1)
    }

    @Test("the device releasing PTT (TX watchdog) stops the microphone")
    func deviceReleases() async throws {
        let microphone = FakeMicrophone()
        var setup = Scripted(microphone: microphone)
        try await setup.ready()
        try await setup.controller.startTransmitting()
        var released = setup.simulator.deviceState
        released.radio.sequence = 100
        setup.transport.streams.deliver(DeviceFrameEncoder.deviceState(released))
        #expect(await setup.snapshots.next { !$0.isTransmitting && $0.desired.sequence == 100 } != nil)
        #expect(microphone.stops == 1)
    }

    @Test("a runaway transmission ends after 180 s")
    func runaway() async throws {
        let microphone = FakeMicrophone()
        var setup = Scripted(microphone: microphone)
        try await setup.ready()
        try await setup.controller.startTransmitting()
        await setup.clock.waitForSleepers(1)
        setup.clock.advance(by: .seconds(179))
        await Task.yield()
        #expect(await setup.controller.snapshot.isTransmitting)
        setup.clock.advance(by: .seconds(1))
        #expect(await eventually { microphone.stops == 1 })
        #expect(await !setup.controller.snapshot.isTransmitting)
    }

    @Test("a runaway timer of an earlier transmission does not end a later one")
    func staleRunaway() async throws {
        let microphone = FakeMicrophone()
        var setup = Scripted(microphone: microphone)
        try await setup.ready()
        try await setup.controller.startTransmitting()
        await setup.clock.waitForSleepers(1)
        setup.clock.advance(by: .seconds(90))
        await setup.controller.stopTransmitting()
        try await setup.controller.startTransmitting()
        await setup.clock.waitForSleepers(1)
        setup.clock.advance(by: .seconds(90))
        for _ in 0..<100 { await Task.yield() }
        #expect(microphone.stops == 1)
        #expect(await setup.controller.snapshot.isTransmitting)
    }

    @Test("disconnect and failures end the transmission")
    func connectionEnds() async throws {
        let microphone = FakeMicrophone()
        var setup = Scripted(microphone: microphone)
        try await setup.ready()
        try await setup.controller.startTransmitting()
        await setup.controller.disconnect()
        #expect(microphone.stops == 1)
        #expect(await !setup.controller.snapshot.isTransmitting)
        _ = await setup.snapshots.next { $0.status == .disconnected }
        try await setup.ready()
        try await setup.controller.startTransmitting()
        setup.transport.streams.publish(.failed(.connectionLost))
        #expect(await eventually { microphone.stops == 2 })
    }

    @Test("a connection that ends while the microphone starts does not transmit")
    func endsWhileStarting() async throws {
        let microphone = FakeMicrophone(holdsStart: true)
        var setup = Scripted(microphone: microphone)
        try await setup.ready()
        let controller = setup.controller
        let pressed = Task { try await controller.startTransmitting() }
        #expect(await eventually { microphone.starts == 1 })
        await controller.disconnect()
        microphone.release()
        try await pressed.value
        #expect(microphone.stops == 2)
        #expect(await !controller.snapshot.isTransmitting)
    }

    @Test("a device report while the microphone starts does not end the transmission")
    func reportWhileStarting() async throws {
        let microphone = FakeMicrophone(holdsStart: true)
        var setup = Scripted(microphone: microphone)
        try await setup.ready()
        let controller = setup.controller
        let pressed = Task { try await controller.startTransmitting() }
        #expect(await eventually { microphone.starts == 1 })
        setup.transport.streams.deliver(DeviceFrameEncoder.deviceState(setup.simulator.deviceState))
        #expect(await eventually { await controller.snapshot.deviceState != nil })
        microphone.release()
        try await pressed.value
        #expect(await controller.snapshot.isTransmitting)
        #expect(microphone.stops == 0)
    }

    @Test("RX audio restarts its fade-in when TX starts and ends")
    func rxAudioReset() async throws {
        let sink = RecordingSink()
        var events = sink.events.makeAsyncIterator()
        var setup = Scripted(microphone: FakeMicrophone(), rxAudio: sink)
        try await setup.ready()
        try await setup.controller.startTransmitting()
        #expect(await events.next() == .reset)
        await setup.controller.stopTransmitting()
        #expect(await events.next() == .reset)
    }
}
