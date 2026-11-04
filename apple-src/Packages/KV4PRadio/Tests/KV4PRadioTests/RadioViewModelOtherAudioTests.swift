import KV4PAudio
import KV4PSimulator
import KV4PTestSupport
import Testing

@testable import KV4PRadio

/// Other apps and the radio screen: the settings, what counts as busy, and PTT (ADR-0043).
@MainActor
@Suite("Radio view model: other audio")
struct RadioViewModelOtherAudioTests {
    @MainActor
    final class Setup {
        let log = CallLog()
        let session: FakeAudioSession
        let store = MemorySettingsStore()
        let clock = ManualClock()
        let microphone = FakeMicrophone()
        let simulator = Box<SimulatorTransport<ManualClock>>()
        let model: RadioViewModel

        init(store: MemorySettingsStore? = nil, outputFails: Bool = false, holdsLowering: Bool = false) {
            let session = FakeAudioSession(log: log, holdsLowering: holdsLowering)
            session.isOtherAudioPlaying = true
            self.session = session
            let simulator = simulator
            let microphone = microphone
            let clock = clock
            model = RadioViewModel(
                makeController: { _, rxAudio in
                    let radioClock = ManualClock()
                    let transport = SimulatorTransport(
                        simulator: RadioSimulator(scenario: .ble),
                        clock: radioClock
                    )
                    simulator.value = transport
                    return RadioController(
                        transport: transport,
                        clock: radioClock,
                        rxAudio: rxAudio,
                        microphone: microphone
                    )
                },
                serialDevices: { [] },
                audioOutput: RecordingOutput(log: log, fails: outputFails),
                audioSession: session,
                settings: store ?? self.store,
                otherAudioSleep: { try await clock.sleep(for: $0) }
            )
        }

        func connected() async {
            await model.connect()
            #expect(await RadioViewModelTests.eventually(model) { $0.isReady && $0.snapshot.isInSync })
            model.frequencyText = "146.52"
            await model.applyFrequency()
            #expect(await RadioViewModelTests.eventually(model) { $0.canTransmit && $0.snapshot.isInSync })
            model.squelch = 3
            #expect(await RadioViewModelTests.eventually(model) { $0.squelch == 3 && $0.snapshot.isInSync })
            log.removeAll()
        }

        func signal() async {
            await simulator.value?.setCarrier(Carrier())
            #expect(await RadioViewModelTests.eventually(model) { $0.isReceiving })
        }

        func until(_ call: String) async -> Bool {
            await KV4PTestSupport.eventually { self.log.calls.contains(call) }
        }
    }

    @Test("the choices are saved and restored, and the default pauses podcasts after 3 s")
    func settings() {
        let setup = Setup()
        #expect(setup.model.otherAudioMode == .pausePodcasts)
        #expect(setup.model.otherAudioResumeSeconds == 3)
        #expect(RadioViewModel.otherAudioResumeOptions == [1, 2, 3, 5, 10])
        setup.model.otherAudioMode = .lower
        setup.model.otherAudioResumeSeconds = 5
        #expect(setup.store.settings.otherAudioMode == .lower)
        #expect(setup.store.settings.otherAudioResumeSeconds == 5)
        let restored = Setup(store: setup.store)
        #expect(restored.model.otherAudioMode == .lower)
        #expect(restored.model.otherAudioResumeSeconds == 5)
    }

    @Test("only a device with an audio session offers the choice")
    func offered() {
        #expect(Setup().model.canChooseOtherAudio)
        #expect(!RadioViewModelTests.model().canChooseOtherAudio)
    }

    @Test("a signal lowers other apps as chosen, and they return after the chosen time")
    func signal() async {
        let setup = Setup()
        await setup.connected()
        setup.model.otherAudioMode = .lower
        setup.model.otherAudioResumeSeconds = 1
        await setup.signal()
        #expect(await setup.until("lower lower"))
        await setup.simulator.value?.setCarrier(nil)
        #expect(await RadioViewModelTests.eventually(setup.model) { !$0.isReceiving })
        await setup.clock.waitForSleepers(1)
        setup.clock.advance(by: .seconds(1))
        #expect(await setup.until("release"))
    }

    @Test("with squelch 0 the squelch is always open, so only PTT lowers other apps, and the settings say so")
    func squelchOff() async {
        let setup = Setup()
        #expect(setup.model.otherAudioHint == nil)
        await setup.connected()
        setup.model.squelch = 0
        #expect(await RadioViewModelTests.eventually(setup.model) { $0.squelch == 0 && $0.snapshot.isInSync })
        await setup.signal()
        #expect(setup.model.otherAudioHint == "While the squelch is 0, only transmitting does this.")
        #expect(!setup.log.calls.contains("lower pausePodcasts"))
        await setup.model.pressPTT()
        #expect(setup.log.calls.contains("silence"))
        await setup.model.releasePTT()
        setup.model.otherAudioMode = .keepPlaying
        #expect(setup.model.otherAudioHint == nil)
    }

    @Test("PTT opens the microphone only after other apps are paused")
    func pttWaits() async {
        let setup = Setup()
        await setup.connected()
        await setup.model.pressPTT()
        #expect(setup.log.calls == ["stop", "silence", "start"])
        #expect(setup.model.isTransmitting)
        #expect(setup.microphone.starts == 1)
    }

    @Test("a PTT released while other apps are being paused does not transmit")
    func pttReleasedEarly() async {
        let setup = Setup(holdsLowering: true)
        await setup.connected()
        let press = Task { await setup.model.pressPTT() }
        #expect(await setup.until("silence"))
        await setup.model.releasePTT()
        setup.session.finishLowering()
        await press.value
        #expect(!setup.model.isTransmitting)
        #expect(setup.microphone.starts == 0)
    }

    @Test("the microphone gets a new engine after each switch")
    func preparesMicrophone() async {
        let setup = Setup()
        await setup.connected()
        let prepared = setup.microphone.prepares
        await setup.signal()
        #expect(await KV4PTestSupport.eventually { setup.microphone.prepares > prepared })
    }

    @Test("a sticky PTT stays on while waiting, and pressing it again ends the transmission")
    func sticky() async {
        let setup = Setup()
        await setup.connected()
        setup.model.isStickyPTT = true
        await setup.model.pressPTT()
        await setup.model.releasePTT()
        #expect(setup.model.isTransmitting)
        await setup.model.pressPTT()
        #expect(!setup.model.isTransmitting)
    }

    @Test("an output that does not start again after a switch is reported")
    func outputFails() async {
        let setup = Setup(outputFails: true)
        await setup.connected()
        setup.model.dismissNotice()
        await setup.signal()
        #expect(
            await RadioViewModelTests.eventually(setup.model) { $0.message == "The audio output cannot be started." }
        )
    }

    @Test("the real sleep waits")
    func systemSleep() async throws {
        try await RadioViewModel.systemSleep(.zero)
    }

    @Test("disconnecting ends the timers, and an interruption starts over")
    func disconnect() async {
        let setup = Setup()
        await setup.connected()
        await setup.signal()
        #expect(await setup.until("lower pausePodcasts"))
        await setup.model.handle(.interruptionBegan)
        setup.log.removeAll()
        await setup.signal()
        #expect(await setup.until("lower pausePodcasts"))
        await setup.model.disconnect()
        setup.log.removeAll()
        setup.clock.advance(by: .seconds(600))
        await Task.yield()
        #expect(!setup.log.calls.contains("release"))
    }

    @Test("after a call, other apps get their sound back")
    func afterInterruption() async {
        let setup = Setup()
        await setup.connected()
        await setup.signal()
        #expect(await setup.until("lower pausePodcasts"))
        await setup.model.handle(.interruptionBegan)
        setup.log.removeAll()
        await setup.model.handle(.interruptionEnded(shouldResume: true))
        #expect(await setup.until("release"))
    }

    @Test("after a call that does not let the radio resume, other apps get their sound back too")
    func afterInterruptionNoResume() async {
        let setup = Setup()
        await setup.connected()
        await setup.signal()
        #expect(await setup.until("lower pausePodcasts"))
        await setup.model.handle(.interruptionBegan)
        setup.log.removeAll()
        await setup.model.handle(.interruptionEnded(shouldResume: false))
        #expect(await setup.until("release"))
        #expect(setup.model.message == "The audio was interrupted. Connect again to listen.")
    }

    // MARK: Mac

    @MainActor
    final class MacSetup {
        let log = CallLog()
        let mute: FakeAudioSession
        let store: MemorySettingsStore
        let model: RadioViewModel

        init(store: MemorySettingsStore = MemorySettingsStore()) {
            self.store = store
            let mute = FakeAudioSession(log: log)
            mute.isOtherAudioPlaying = true
            self.mute = mute
            model = RadioViewModel(
                makeController: { _, rxAudio in
                    let clock = ManualClock()
                    let transport = SimulatorTransport(simulator: RadioSimulator(scenario: .ble), clock: clock)
                    return RadioController(transport: transport, clock: clock, rxAudio: rxAudio)
                },
                serialDevices: { [] },
                audioOutput: RecordingOutput(log: log),
                otherAppsMute: mute,
                settings: store
            )
        }
    }

    @Test("a Mac offers muting, and starts with Keep playing, also with what an older version stored")
    func macModes() {
        let setup = MacSetup()
        #expect(setup.model.canChooseOtherAudio)
        #expect(setup.model.otherAudioModes == [.keepPlaying, .muteAll])
        #expect(setup.model.otherAudioMode == .keepPlaying)
        #expect(Setup().model.otherAudioModes == [.keepPlaying, .lower, .pausePodcasts])
    }

    @Test("choosing to mute is stored and switches nothing yet")
    func macChooses() async {
        let setup = MacSetup()
        setup.log.removeAll()
        setup.model.otherAudioMode = .muteAll
        #expect(setup.store.settings.otherAudioMode == .muteAll)
        #expect(MacSetup(store: setup.store).model.otherAudioMode == .muteAll)
        await Task.yield()
        #expect(setup.log.calls.isEmpty)
    }

    @Test("a signal mutes other apps without touching the radio's own output")
    func macMutes() async {
        let setup = MacSetup()
        await setup.model.connect()
        #expect(await RadioViewModelTests.eventually(setup.model) { $0.isReady && $0.snapshot.isInSync })
        setup.model.otherAudioMode = .muteAll
        setup.log.removeAll()
        await setup.model.pressPTT()
        #expect(setup.log.calls.contains("silence"))
        #expect(!setup.log.calls.contains("stop"))
    }
}
