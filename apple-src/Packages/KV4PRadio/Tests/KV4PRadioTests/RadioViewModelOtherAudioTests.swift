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

        init(store: MemorySettingsStore? = nil) {
            let session = FakeAudioSession(log: log)
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
                audioOutput: RecordingOutput(log: log),
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
        #expect(setup.log.calls.contains("lower pausePodcasts"))
        await setup.model.releasePTT()
        setup.model.otherAudioMode = .keepPlaying
        #expect(setup.model.otherAudioHint == nil)
    }

    @Test("PTT opens the microphone only after other apps are lowered")
    func pttWaits() async {
        let setup = Setup()
        await setup.connected()
        await setup.model.pressPTT()
        #expect(setup.log.calls == ["stop", "lower pausePodcasts", "start"])
        #expect(setup.model.isTransmitting)
        #expect(setup.microphone.starts == 1)
    }

    @Test("a PTT released while other apps are being lowered does not transmit")
    func pttReleasedEarly() async {
        let setup = Setup()
        await setup.connected()
        let press = Task { await setup.model.pressPTT() }
        await Task.yield()
        await setup.model.releasePTT()
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
}
