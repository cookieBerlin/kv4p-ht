import KV4PAudio
import KV4PSimulator
import KV4PTestSupport
import Synchronization
import Testing

@testable import KV4PProtocol
@testable import KV4PRadio

/// Sending the tone that opens a repeater, without the microphone (ADR-0045).
@Suite("Radio controller access tone")
struct AccessToneControllerTests {
    static let tone = AccessTone(frequency: 1750, lengthMs: 250, waitMs: 100)
    static let blockPeriod = Duration.seconds(Double(KV4P.audioBlockSamples) / Double(KV4P.audioSampleRate))

    struct Setup {
        let clock = ManualClock()
        let transport = ScriptedTransport()
        let microphone = FakeMicrophone()
        let sink = RecordingSink()
        let controller: RadioController<ManualClock>
        var simulator: RadioSimulator
        var snapshots: AsyncStream<RadioSnapshot>.Iterator

        init(scenario: Scenario = .ble) {
            simulator = RadioSimulator(scenario: scenario)
            controller = RadioController(transport: transport, clock: clock, rxAudio: sink, microphone: microphone)
            snapshots = controller.snapshots.makeAsyncIterator()
        }

        mutating func ready() async throws {
            await controller.connect()
            transport.streams.deliver(simulator.connect(at: .zero))
            _ = try #require(await snapshots.next { $0.status == .ready })
            try await controller.tune(rx: 146.52, tx: 146.52)
        }

        /// The radio reports that it transmits.
        func reportOnAir() {
            var state = simulator.deviceState
            state.radio.flags.insert(.txActive)
            state.radio.sequence = 0
            transport.streams.deliver(DeviceFrameEncoder.deviceState(state))
        }

        /// The blocks of TX audio sent so far, decoded.
        var sentAudio: [[Int16]] {
            var parser = HostFrameParser()
            var blocks: [[Int16]] = []
            for bytes in transport.sent {
                for parsed in parser.process(bytes) {
                    if case .command(.txAudio, let payload) = parsed.content {
                        blocks.append(ImaAdpcm.decodeBlock(payload, maxSamples: KV4P.audioBlockSamples))
                    }
                }
            }
            return blocks
        }

        /// Lets block after block pass until `task` ends.
        func run<T: Sendable>(until task: Task<T, any Error>) async throws -> T {
            let done = Box<Bool>()
            let watcher = Task {
                _ = try? await task.value
                done.value = true
            }
            while done.value != true {
                clock.advance(by: AccessToneControllerTests.blockPeriod)
                await Task.yield()
            }
            await watcher.value
            return try await task.value
        }
    }

    @Test("sends silence until the radio transmits and the wait has passed, then the tone, then stops by itself")
    func sends() async throws {
        var setup = Setup()
        try await setup.ready()
        let controller = setup.controller
        let task = Task { try await controller.sendAccessTone(Self.tone) }
        _ = try #require(await setup.snapshots.next { $0.isSendingAccessTone && $0.isTransmitting })
        await setup.clock.waitForSleepers(1)
        setup.clock.advance(by: Self.blockPeriod * 8)
        setup.reportOnAir()
        let result = try await setup.run(until: task)
        #expect(result == .finished)

        // The last blocks may still be on their way to the transport.
        let toneBlocks = Self.tone.samples().count / KV4P.audioBlockSamples
        let isLoud: ([Int16]) -> Bool = { ($0.map { abs(Int($0)) }.max() ?? 0) > 4000 }
        let sender = setup
        #expect(await eventually { sender.sentAudio.count(where: isLoud) >= toneBlocks - 2 })
        let audio = setup.sentAudio
        let loud = audio.indices.filter { isLoud(audio[$0]) }
        #expect(try #require(loud.first) >= 8)  // silence while waiting for the radio
        #expect(abs(loud.count - toneBlocks) <= 2)

        let snapshot = await controller.snapshot
        #expect(!snapshot.isSendingAccessTone)
        #expect(!snapshot.isTransmitting)
        #expect(setup.microphone.starts == 0)
    }

    @Test("the tone is played on the device too, without the fade-in")
    func playsOnDevice() async throws {
        var setup = Setup()
        try await setup.ready()
        var events = setup.sink.events.makeAsyncIterator()
        let controller = setup.controller
        let task = Task { try await controller.sendAccessTone(Self.tone) }
        await setup.clock.waitForSleepers(1)
        setup.reportOnAir()
        _ = try await setup.run(until: task)
        var heard = 0
        while let event = await events.next() {
            if case .tone(let samples) = event { heard += samples.count }
            if heard >= Self.tone.samples().count { break }
        }
        #expect(heard >= Self.tone.samples().count)
    }

    @Test("the microphone gain does not raise the level of the tone")
    func ignoresMicGain() async throws {
        var setup = Setup()
        try await setup.ready()
        await setup.controller.setMicGain(.high)
        let controller = setup.controller
        let task = Task { try await controller.sendAccessTone(Self.tone) }
        await setup.clock.waitForSleepers(1)
        setup.reportOnAir()
        _ = try await setup.run(until: task)
        let peak = setup.sentAudio.flatMap { $0 }.map { abs(Int($0)) }.max() ?? 0
        #expect(peak < 20000)
    }

    @Test("without a report from the radio within 2 s, it stops without a tone")
    func notOnAir() async throws {
        var setup = Setup()
        try await setup.ready()
        let controller = setup.controller
        let task = Task { try await controller.sendAccessTone(Self.tone) }
        await setup.clock.waitForSleepers(1)
        setup.clock.advance(by: .milliseconds(1900))
        await setup.clock.waitForSleepers(1)  // the next block is due: it still waits
        #expect(await controller.snapshot.isSendingAccessTone)
        setup.clock.advance(by: .milliseconds(200))
        #expect(try await task.value == .radioNotTransmitting)
        let peak = setup.sentAudio.flatMap { $0 }.map { abs(Int($0)) }.max() ?? 0
        #expect(peak < 4000)
        #expect(await !controller.snapshot.isTransmitting)
    }

    @Test("stopping ends the transmission at once and says so")
    func stops() async throws {
        var setup = Setup()
        try await setup.ready()
        let controller = setup.controller
        let task = Task { try await controller.sendAccessTone(Self.tone) }
        _ = try #require(await setup.snapshots.next { $0.isSendingAccessTone })
        await setup.clock.waitForSleepers(1)
        await controller.stopTransmitting()
        setup.clock.advance(by: Self.blockPeriod)
        #expect(try await task.value == .stopped)
        #expect(await !controller.snapshot.isSendingAccessTone)
    }

    @Test("it needs a ready radio, a free transmitter, analog voice and an allowed frequency")
    func guards() async throws {
        let waiting = RadioController(transport: ScriptedTransport(), clock: ManualClock())
        await #expect(throws: RadioError.notReady) { try await waiting.sendAccessTone(Self.tone) }

        var setup = Setup()
        try await setup.ready()
        var limits = TXLimits()
        limits.max2m = 146
        await setup.controller.setTXLimits(limits)
        await #expect(throws: RadioError.transmitNotAllowed) { try await setup.controller.sendAccessTone(Self.tone) }
        await setup.controller.setTXLimits(TXLimits())
        try await setup.controller.startTransmitting()
        await #expect(throws: RadioError.busy) { try await setup.controller.sendAccessTone(Self.tone) }
        await setup.controller.stopTransmitting()

        var scenario = Scenario.ble
        scenario.features.insert(.freeDV2400B)
        var digital = Setup(scenario: scenario)
        try await digital.ready()
        await digital.controller.update { $0.setFreeDV(true) }
        await #expect(throws: RadioError.busy) { try await digital.controller.sendAccessTone(Self.tone) }
    }
}
