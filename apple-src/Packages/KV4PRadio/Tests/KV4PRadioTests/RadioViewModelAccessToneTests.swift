import KV4PAudio
import KV4PPersistence
import KV4PSimulator
import KV4PTestSupport
import KV4PTransport
import Testing

@testable import KV4PProtocol
@testable import KV4PRadio

/// The button that opens a repeater, its settings and what it tells the user (ADR-0045).
@MainActor
@Suite("Radio view model: access tone")
struct RadioViewModelAccessToneTests {
    @MainActor
    final class Setup {
        let log = CallLog()
        let clock = ManualClock()
        let store: MemorySettingsStore
        let microphone = FakeMicrophone()
        let session: FakeAudioSession
        let permissions = FakePermissions()
        let model: RadioViewModel

        init(store: MemorySettingsStore = MemorySettingsStore(), scenario: Scenario = .ble, respond: Bool = true) {
            self.store = store
            let session = FakeAudioSession(log: log)
            session.isOtherAudioPlaying = true
            self.session = session
            let clock = clock
            let microphone = microphone
            var scenario = scenario
            scenario.startFrequency = 146.52
            let frozenScenario = scenario
            model = RadioViewModel(
                makeController: { _, rxAudio in
                    var simulator = RadioSimulator(scenario: frozenScenario)
                    let hello = simulator.connect(at: .zero)
                    let transport: any RadioTransport =
                        respond
                        ? SimulatorTransport(simulator: RadioSimulator(scenario: frozenScenario), clock: clock)
                        : ScriptedTransport { $0.deliver(hello) }
                    return RadioController(transport: transport, clock: clock, rxAudio: rxAudio, microphone: microphone)
                },
                serialDevices: { [] },
                audioOutput: RecordingOutput(log: log),
                audioSession: session,
                memories: try? SwiftDataMemoryRepository.inMemory(),
                settings: store,
                permissions: permissions
            )
        }

        func connected() async {
            await model.connect()
            #expect(await RadioViewModelTests.eventually(model) { $0.isReady && $0.snapshot.isInSync })
            log.removeAll()
        }

        /// Lets time pass until `task` ends.
        func run(until task: Task<Void, Never>) async {
            let done = Box<Bool>()
            let watcher = Task {
                await task.value
                done.value = true
            }
            while done.value != true {
                clock.advance(by: .milliseconds(10))
                await Task.yield()
            }
            await watcher.value
        }
    }

    @Test("the defaults: no tone, 1 s, a wait of 200 ms; the choices are saved and restored")
    func settings() {
        let setup = Setup()
        #expect(setup.model.accessToneHz == 0)
        #expect(setup.model.accessToneLengthMs == 1000)
        #expect(setup.model.accessToneWaitMs == 200)
        #expect(setup.model.accessTone == nil)
        setup.model.accessToneHz = 1750
        setup.model.accessToneLengthMs = 2000
        setup.model.accessToneWaitMs = 500
        #expect(setup.model.accessTone == AccessTone(frequency: 1750, lengthMs: 2000, waitMs: 500))
        let restored = Setup(store: setup.store)
        #expect(restored.model.accessTone == AccessTone(frequency: 1750, lengthMs: 2000, waitMs: 500))
    }

    @Test("the memory tuned to takes precedence over the settings, for each value on its own")
    func memoryPrecedence() async throws {
        let setup = Setup()
        await setup.connected()
        setup.model.accessToneHz = 1750
        await setup.model.save(
            ChannelMemory(name: "Own", frequency: 146.94, accessToneHz: 1450, accessToneLengthMs: 3000)
        )
        await setup.model.save(ChannelMemory(name: "Follows", frequency: 146.52))
        await setup.model.save(ChannelMemory(name: "Length", frequency: 146.7, accessToneLengthMs: 500))
        await setup.model.save(ChannelMemory(name: "Off", frequency: 146.8, accessToneHz: 0))
        let memories = setup.model.memories

        await setup.model.tune(to: memories[0])
        #expect(setup.model.accessTone == AccessTone(frequency: 1450, lengthMs: 3000, waitMs: 200))
        await setup.model.tune(to: memories[1])
        #expect(setup.model.accessTone == AccessTone(frequency: 1750, lengthMs: 1000, waitMs: 200))
        await setup.model.tune(to: memories[2])
        #expect(setup.model.accessTone == AccessTone(frequency: 1750, lengthMs: 500, waitMs: 200))
        await setup.model.tune(to: memories[3])
        #expect(setup.model.accessTone == nil)
    }

    @Test("the button needs a tone, a radio, the microphone permission and analog voice")
    func offered() async {
        let setup = Setup(scenario: .freeDV)
        #expect(!setup.model.canSendAccessTone)
        setup.model.accessToneHz = 1750
        #expect(!setup.model.canSendAccessTone)  // no radio
        await setup.connected()
        #expect(setup.model.canSendAccessTone)
        setup.permissions.set(.microphone, .denied)
        #expect(await RadioViewModelTests.eventually(setup.model) { !$0.canSendAccessTone })
        setup.permissions.set(.microphone, .granted)
        #expect(await RadioViewModelTests.eventually(setup.model) { $0.canSendAccessTone })
        setup.model.isFreeDV = true
        #expect(await RadioViewModelTests.eventually(setup.model) { !$0.canSendAccessTone })
    }

    @Test("holding sends the tone, without the microphone, without touching other apps, and without a message")
    func sends() async {
        let setup = Setup()
        await setup.connected()
        setup.model.accessToneHz = 1750
        setup.model.accessToneLengthMs = 250
        setup.model.accessToneWaitMs = 0
        let press = Task { await setup.model.pressAccessTone() }
        #expect(await RadioViewModelTests.eventually(setup.model) { $0.isSendingAccessTone })
        await setup.run(until: press)
        #expect(!setup.model.isSendingAccessTone)
        #expect(!setup.model.isTransmitting)
        #expect(setup.model.message == nil)
        #expect(setup.microphone.starts == 0)
        #expect(!setup.log.calls.contains { $0.hasPrefix("lower") || $0 == "silence" })
    }

    @Test("releasing early stops at once and says that the repeater may not have opened")
    func released() async {
        let setup = Setup()
        await setup.connected()
        setup.model.accessToneHz = 1750
        let press = Task { await setup.model.pressAccessTone() }
        #expect(await RadioViewModelTests.eventually(setup.model) { $0.isSendingAccessTone })
        await setup.model.releaseAccessTone()
        await setup.run(until: press)
        #expect(!setup.model.isTransmitting)
        #expect(setup.model.message == "The tone was cut short, so the repeater may not have opened.")
    }

    @Test("a radio that does not transmit within 2 s is reported")
    func notTransmitting() async {
        let setup = Setup(respond: false)
        await setup.model.connect()
        #expect(await RadioViewModelTests.eventually(setup.model) { $0.isReady })
        setup.model.frequencyText = "146.52"
        await setup.model.applyFrequency()
        #expect(await RadioViewModelTests.eventually(setup.model) { $0.snapshot.desired.flags.contains(.txAllowed) })
        setup.model.accessToneHz = 1750
        let press = Task { await setup.model.pressAccessTone() }
        await setup.run(until: press)
        #expect(setup.model.message == "The radio did not start transmitting, so no tone went out.")
    }

    @Test("on a frequency that may not transmit, the text on screen says why, and no message adds to it")
    func blocked() async {
        let setup = Setup()
        await setup.connected()
        setup.model.accessToneHz = 1750
        var limits = TXLimits()
        limits.max2m = 146
        setup.model.txLimits = limits
        #expect(await RadioViewModelTests.eventually(setup.model) { !$0.canTransmit })
        await setup.model.pressAccessTone()
        #expect(setup.model.message == nil)
        #expect(!setup.model.isTransmitting)
    }

    @Test("without a tone or a radio, the button does nothing")
    func nothing() async {
        let setup = Setup()
        await setup.model.pressAccessTone()
        await setup.model.releaseAccessTone()
        setup.model.accessToneHz = 1750
        await setup.model.pressAccessTone()
        #expect(setup.model.message == nil)
    }

    @Test("another problem is reported")
    func busy() async {
        let setup = Setup()
        await setup.connected()
        setup.model.accessToneHz = 1750
        await setup.model.pressPTT()
        await setup.model.pressAccessTone()
        #expect(setup.model.message != nil)
    }
}
