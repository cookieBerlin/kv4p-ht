import KV4PAudio
import KV4PSimulator
import KV4PTestSupport
import Synchronization
import Testing

@testable import KV4PProtocol
@testable import KV4PRadio

/// An audio session that records its calls into a log it shares with a `RecordingOutput`, and sends events on demand.
final class FakeAudioSession: AudioSession {
    struct Failure: Error {}

    let events: AsyncStream<AudioSessionEvent>
    private let continuation: AsyncStream<AudioSessionEvent>.Continuation
    private let log: CallLog
    private let fails: Bool

    init(log: CallLog, fails: Bool = false) {
        (events, continuation) = AsyncStream.makeStream()
        self.log = log
        self.fails = fails
    }

    func activate() throws {
        log.append("activate")
        if fails { throw Failure() }
    }

    func deactivate() {
        log.append("deactivate")
    }

    func send(_ event: AudioSessionEvent) {
        continuation.yield(event)
    }
}

/// The iOS audio session: activated with the audio, and calls or lost devices end a transmission.
@MainActor
@Suite("Radio view model audio session")
struct RadioViewModelAudioSessionTests {
    @MainActor
    final class Setup {
        let log = CallLog()
        let session: FakeAudioSession
        let simulator = Box<SimulatorTransport<ManualClock>>()
        let model: RadioViewModel

        init(sessionFails: Bool = false) {
            session = FakeAudioSession(log: log, fails: sessionFails)
            let simulator = simulator
            model = RadioViewModel(
                makeController: { _, rxAudio in
                    let clock = ManualClock()
                    let transport = SimulatorTransport(simulator: RadioSimulator(scenario: .ble), clock: clock)
                    simulator.value = transport
                    return RadioController(
                        transport: transport,
                        clock: clock,
                        rxAudio: rxAudio,
                        microphone: FakeMicrophone()
                    )
                },
                serialDevices: { [] },
                audioOutput: RecordingOutput(log: log),
                audioSession: session
            )
        }

        /// Connected, tuned into the band and transmitting with sticky PTT.
        func transmitting() async {
            await model.connect()
            #expect(await RadioViewModelTests.eventually(model) { $0.isReady && $0.snapshot.isInSync })
            model.frequencyText = "146.52"
            await model.applyFrequency()
            #expect(await RadioViewModelTests.eventually(model) { $0.canTransmit && $0.snapshot.isInSync })
            model.isStickyPTT = true
            await model.pressPTT()
            #expect(model.isTransmitting)
            log.removeAll()
        }

        func send(_ event: AudioSessionEvent, until condition: @escaping (RadioViewModel) -> Bool) async {
            session.send(event)
            #expect(await RadioViewModelTests.eventually(model, condition))
        }
    }

    @Test("connecting activates the session before the audio starts, disconnecting deactivates it after")
    func activation() async {
        let setup = Setup()
        await setup.model.connect()
        #expect(setup.log.calls == ["stop", "deactivate", "activate", "start"])
        await setup.model.disconnect()
        #expect(setup.log.calls == ["stop", "deactivate", "activate", "start", "stop", "deactivate"])
    }

    @Test("a session that cannot be activated is reported, the radio still connects")
    func activationFails() async {
        let setup = Setup(sessionFails: true)
        await setup.model.connect()
        #expect(await RadioViewModelTests.eventually(setup.model) { $0.isReady })
        #expect(setup.model.message == "The audio output cannot be started.")
        #expect(!setup.log.calls.contains("start"))
    }

    @Test("an interruption ends the transmission and the audio; it resumes when the system allows it")
    func interruption() async {
        let setup = Setup()
        await setup.transmitting()
        await setup.send(.interruptionBegan) { !$0.isTransmitting }
        #expect(setup.log.calls == ["stop"])
        await setup.send(.interruptionEnded(shouldResume: true)) { _ in setup.log.calls.count == 3 }
        #expect(setup.log.calls == ["stop", "activate", "start"])
        #expect(setup.model.message == nil)
    }

    @Test("an interruption that must not resume leaves the audio off and says so")
    func interruptionWithoutResume() async {
        let setup = Setup()
        await setup.transmitting()
        await setup.model.handle(.interruptionBegan)
        await setup.model.handle(.interruptionEnded(shouldResume: false))
        #expect(setup.model.message == "The audio was interrupted. Connect again to listen.")
        #expect(setup.log.calls == ["stop"])
    }

    @Test("a lost audio device ends the transmission, the audio keeps playing")
    func deviceUnavailable() async {
        let setup = Setup()
        await setup.transmitting()
        await setup.model.handle(.deviceUnavailable)
        #expect(!setup.model.isTransmitting)
        #expect(setup.log.calls.isEmpty)
    }

    @Test("after a reset of the media services the audio starts again")
    func mediaServicesReset() async {
        let setup = Setup()
        await setup.transmitting()
        await setup.model.handle(.mediaServicesReset)
        #expect(!setup.model.isTransmitting)
        #expect(setup.log.calls == ["stop", "activate", "start"])
    }

    @Test("events while disconnected change nothing")
    func disconnected() async {
        let setup = Setup()
        await setup.model.handle(.interruptionEnded(shouldResume: true))
        await setup.model.handle(.mediaServicesReset)
        #expect(setup.log.calls.isEmpty)
        #expect(setup.model.message == nil)
    }
}
