import KV4PAudio
import KV4PDigital
import KV4PSimulator
import KV4PTestSupport
import Testing

@testable import KV4PProtocol
@testable import KV4PRadio

/// FreeDV 2400B in `RadioAudioService`: `setFreeDv2400bEnabled`, `handleRxDigital`, `sendFreeDvAudio`.
@Suite("Radio controller FreeDV")
struct FreeDVControllerTests {
    static let frame: [UInt8] = [0xF2, 0xF4, 0x06, 0x57, 0x5C, 0xDD, 0x20]
    static let speech = (0..<1280).map { Int16(truncatingIfNeeded: $0 * 211 % 16000 - 8000) }

    static var freeDVScenario: Scenario {
        var scenario = Scenario.ble
        scenario.features.insert(.freeDV2400B)
        return scenario
    }

    /// A ready radio on a scripted transport, its RX audio recorded.
    struct Scripted {
        let transport = ScriptedTransport()
        let sink = RecordingSink()
        let microphone = FakeMicrophone()
        let controller: RadioController<ManualClock>
        var snapshots: AsyncStream<RadioSnapshot>.Iterator
        var events: AsyncStream<RecordingSink.Event>.Iterator
        var simulator: RadioSimulator

        init(
            scenario: Scenario = FreeDVControllerTests.freeDVScenario,
            digitalVoice: @escaping @Sendable () -> FreeDVVoice? = { FreeDVVoice() }
        ) {
            simulator = RadioSimulator(scenario: scenario)
            controller = RadioController(
                transport: transport,
                clock: ManualClock(),
                rxAudio: sink,
                microphone: microphone,
                digitalVoice: digitalVoice
            )
            snapshots = controller.snapshots.makeAsyncIterator()
            events = sink.events.makeAsyncIterator()
        }

        mutating func ready() async throws {
            await controller.connect()
            transport.streams.deliver(simulator.connect(at: .zero))
            _ = try #require(await snapshots.next { $0.status == .ready })
        }
    }

    @Test("FreeDV is switched on only if the firmware supports it")
    func firmwareSupport() async throws {
        var analog = Scripted(scenario: .ble)
        try await analog.ready()
        await analog.controller.setFreeDV(true)
        #expect(await !analog.controller.snapshot.supportsFreeDV)
        #expect(await !analog.controller.snapshot.isFreeDV)
        var digital = Scripted()
        try await digital.ready()
        #expect(await digital.controller.snapshot.supportsFreeDV)
        await digital.controller.setFreeDV(true)
        #expect(await digital.controller.snapshot.isFreeDV)
        await digital.controller.setFreeDV(false)
        #expect(await !digital.controller.snapshot.isFreeDV)
    }

    @Test("without Codec2 FreeDV stays off")
    func codecUnavailable() async throws {
        var setup = Scripted(digitalVoice: { nil })
        try await setup.ready()
        await setup.controller.setFreeDV(true)
        #expect(await !setup.controller.snapshot.isFreeDV)
    }

    @Test("received frames play as 16 kHz samples; other lengths and frames outside FreeDV are dropped")
    func receive() async throws {
        var setup = Scripted()
        try await setup.ready()
        setup.transport.streams.deliver(DeviceFrameEncoder.rxDigital(Self.frame))  // analog: dropped
        await setup.controller.setFreeDV(true)
        setup.transport.streams.deliver(DeviceFrameEncoder.rxDigital([1, 2, 3]))
        setup.transport.streams.deliver(DeviceFrameEncoder.rxDigital(Self.frame))
        guard case .samples(let samples) = await setup.events.next() else {
            Issue.record("expected samples")
            return
        }
        #expect(samples.count == 2 * Codec2.samplesPerFrame)
        #expect(stride(from: 0, to: samples.count, by: 2).allSatisfy { samples[$0] == samples[$0 + 1] })
    }

    @Test("while transmitting, received frames are not played")
    func receiveWhileTransmitting() async throws {
        var setup = Scripted()
        try await setup.ready()
        await setup.controller.setFreeDV(true)
        try await setup.controller.tune(rx: 146.52, tx: 146.52)
        try await setup.controller.startTransmitting()
        #expect(await setup.events.next() == .reset)
        // The device state after the frame shows that the frame was handled.
        let transmitting = DeviceState(
            radio: setup.simulator.deviceState.radio,
            radioModuleStatus: .found,
            mode: .tx,
            latestRssi: 0
        )
        setup.transport.streams.deliver(
            DeviceFrameEncoder.rxDigital(Self.frame) + DeviceFrameEncoder.deviceState(transmitting)
        )
        _ = try #require(await setup.snapshots.next { $0.deviceState?.mode == .tx })
        await setup.controller.stopTransmitting()
        #expect(await setup.events.next() == .reset)
    }

    @Test("the microphone with its gain is sent as Codec2 frames")
    func transmit() async throws {
        let clock = ManualClock()
        let microphone = FakeMicrophone()
        let transport = SimulatorTransport(simulator: RadioSimulator(scenario: Self.freeDVScenario), clock: clock)
        let controller = RadioController(transport: transport, clock: clock, microphone: microphone)
        var snapshots = controller.snapshots.makeAsyncIterator()
        await controller.connect()
        _ = try #require(await snapshots.next { $0.status == .ready && $0.isInSync })
        try await controller.tune(rx: 146.52, tx: 146.52)
        await controller.setFreeDV(true)
        await controller.setMicGain(.med)
        _ = try #require(
            await snapshots.next { $0.isInSync && $0.isFreeDV && $0.desired.flags.contains(.txAllowed) }
        )
        try await controller.startTransmitting()
        #expect(await eventually { await transport.simulator.deviceState.mode == .tx })
        microphone.speak(Array(Self.speech[..<101]))
        microphone.speak(Array(Self.speech[101...]))
        #expect(await eventually { await transport.simulator.transmittedDigitalFrames == 2 })
        let reference = try #require(FreeDVVoice())
        reference.gain = .med
        #expect(await transport.simulator.lastTransmittedDigital == reference.encode(Self.speech).last)
        #expect(await transport.simulator.transmittedAudioBlocks == 0)
        await controller.stopTransmitting()
    }
}
