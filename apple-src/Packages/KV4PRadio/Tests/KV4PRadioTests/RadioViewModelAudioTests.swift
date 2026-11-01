import KV4PAudio
import KV4PSimulator
import KV4PTestSupport
import Synchronization
import Testing

@testable import KV4PProtocol
@testable import KV4PRadio

/// The calls of audio test doubles, in order.
final class CallLog: Sendable {
    private let entries = Mutex<[String]>([])

    var calls: [String] { entries.withLock { $0 } }

    func append(_ call: String) {
        entries.withLock { $0.append(call) }
    }

    func removeAll() {
        entries.withLock { $0.removeAll() }
    }
}

/// Records start and stop of the audio output.
final class RecordingOutput: AudioOutput {
    struct Failure: Error {}

    private let calls: CallLog
    private let fails: Bool

    init(log: CallLog = CallLog(), fails: Bool = false) {
        calls = log
        self.fails = fails
    }

    var log: [String] { calls.calls }

    func start(_ player: RXAudioPlayer) throws {
        calls.append("start")
        if fails { throw Failure() }
    }

    func stop() {
        calls.append("stop")
    }
}

/// RX audio, squelch and the simulated signal of the radio screen.
@MainActor
@Suite("Radio view model audio")
struct RadioViewModelAudioTests {
    /// A model whose connections are served by one simulator; `simulator` reaches it once connected.
    @MainActor
    final class Setup {
        let output: RecordingOutput
        let simulator = Box<SimulatorTransport<ManualClock>>()
        let model: RadioViewModel

        init(_ scenario: Scenario = .ble, output: RecordingOutput = RecordingOutput()) {
            self.output = output
            let simulator = simulator
            model = RadioViewModel(
                makeController: { _, rxAudio in
                    let clock = ManualClock()
                    let transport = SimulatorTransport(simulator: RadioSimulator(scenario: scenario), clock: clock)
                    simulator.value = transport
                    return RadioController(transport: transport, clock: clock, rxAudio: rxAudio)
                },
                serialDevices: { [] },
                audioOutput: output,
                simulateSignal: { await simulator.value?.setCarrier($0 ? Carrier() : nil) }
            )
        }

        func connect(_ connection: RadioViewModel.Connection = .simulator) async {
            model.selectedConnection = connection
            await model.connect()
            #expect(await RadioViewModelTests.eventually(model) { $0.isReady && $0.snapshot.isInSync })
        }
    }

    @Test("connecting starts the audio output, disconnecting stops it")
    func output() async {
        let setup = Setup()
        await setup.connect()
        #expect(setup.output.log == ["stop", "start"])
        await setup.model.disconnect()
        #expect(setup.output.log == ["stop", "start", "stop"])
    }

    @Test("an audio output that cannot start is reported, the radio still connects")
    func outputFails() async {
        let setup = Setup(output: RecordingOutput(fails: true))
        await setup.connect()
        #expect(setup.model.message == "The audio output cannot be started.")
    }

    @Test("the squelch indication follows the radio")
    func receiving() async {
        let idle = Setup()
        #expect(!idle.model.isReceiving)
        await idle.connect()
        #expect(!idle.model.isReceiving)
        var scenario = Scenario.ble
        scenario.carrier = Carrier()
        let busy = Setup(scenario)
        await busy.connect()
        #expect(busy.model.isReceiving)
    }

    @Test("the volume applies to the RX audio, 0…1")
    func volume() {
        let model = Setup().model
        #expect(model.volume == 1)
        model.volume = 0.25
        #expect(model.volume == 0.25)
        #expect(model.rxAudio.volume == 0.25)
    }

    @Test("the simulator can simulate a received signal")
    func simulatedSignal() async {
        let setup = Setup()
        #expect(!setup.model.canSimulateSignal)
        await setup.connect()
        #expect(setup.model.canSimulateSignal)
        setup.model.isSignalSimulated = true
        #expect(await RadioViewModelTests.eventually(setup.model) { $0.isReceiving })
        setup.model.isSignalSimulated = false
        #expect(await RadioViewModelTests.eventually(setup.model) { !$0.isReceiving })
        setup.model.isSignalSimulated = true
        await setup.model.disconnect()
        #expect(!setup.model.isSignalSimulated)
    }

    @Test("a real radio cannot simulate a signal")
    func noSimulatedSignal() async {
        let setup = Setup()
        await setup.connect(.bluetooth)
        #expect(!setup.model.canSimulateSignal)
        let plain = RadioViewModelTests.model()
        plain.selectedConnection = .simulator
        await plain.connect()
        #expect(await RadioViewModelTests.eventually(plain) { $0.isReady })
        #expect(!plain.canSimulateSignal)
    }
}
