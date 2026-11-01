import KV4PAudio
import KV4PSimulator
import KV4PTestSupport
import Testing

@testable import KV4PProtocol
@testable import KV4PRadio

/// PTT (hold or sticky), mic gain and TX messages of the radio screen (Android `MainActivity.handlePttPress`).
@MainActor
@Suite("Radio view model transmit")
struct RadioViewModelTransmitTests {
    @MainActor
    final class Setup {
        let microphone: FakeMicrophone
        let simulator = Box<SimulatorTransport<ManualClock>>()
        let model: RadioViewModel

        init(microphone: FakeMicrophone = FakeMicrophone()) {
            self.microphone = microphone
            let simulator = simulator
            model = RadioViewModel(
                makeController: { _, rxAudio in
                    let clock = ManualClock()
                    let transport = SimulatorTransport(simulator: RadioSimulator(scenario: .ble), clock: clock)
                    simulator.value = transport
                    return RadioController(transport: transport, clock: clock, rxAudio: rxAudio, microphone: microphone)
                },
                serialDevices: { [] }
            )
        }

        /// Connected and tuned to `frequency`.
        func tuned(_ frequency: String = "146.52") async {
            await model.connect()
            #expect(await RadioViewModelTests.eventually(model) { $0.isReady && $0.snapshot.isInSync })
            model.frequencyText = frequency
            await model.applyFrequency()
            #expect(
                await RadioViewModelTests.eventually(model) {
                    $0.snapshot.isInSync && $0.snapshot.deviceState?.radio.freqTx == Float(frequency)
                }
            )
        }

        var deviceMode: DeviceMode? {
            get async { await simulator.value?.simulator.deviceState.mode }
        }
    }

    @Test("holding PTT transmits until it is released")
    func hold() async {
        let setup = Setup()
        #expect(!setup.model.canTransmit)
        await setup.tuned()
        #expect(setup.model.canTransmit)
        await setup.model.pressPTT()
        #expect(setup.model.isTransmitting)
        #expect(await RadioViewModelTests.eventually(setup.model) { $0.isOnAir })
        #expect(await setup.deviceMode == .tx)
        await setup.model.releasePTT()
        #expect(!setup.model.isTransmitting)
        #expect(setup.microphone.stops == 1)
    }

    @Test("sticky PTT toggles with each press and ignores releases")
    func sticky() async {
        let setup = Setup()
        await setup.tuned()
        setup.model.isStickyPTT = true
        await setup.model.pressPTT()
        await setup.model.releasePTT()
        #expect(setup.model.isTransmitting)
        await setup.model.pressPTT()
        #expect(!setup.model.isTransmitting)
        #expect(setup.microphone.stops == 1)
    }

    @Test("outside the ham band PTT explains why it does not transmit")
    func outsideBand() async {
        let setup = Setup()
        await setup.tuned("150")
        #expect(!setup.model.canTransmit)
        await setup.model.pressPTT()
        #expect(setup.model.message == "Can't transmit outside the ham band.")
        #expect(!setup.model.isTransmitting)
    }

    @Test("a missing microphone permission is explained")
    func microphoneDenied() async {
        let setup = Setup(microphone: FakeMicrophone(fails: true))
        await setup.tuned()
        await setup.model.pressPTT()
        #expect(
            setup.model.message
                == "The microphone is not available. Allow access in System Settings → Privacy & Security → Microphone."
        )
    }

    @Test("PTT before connecting does nothing")
    func notConnected() async {
        let setup = Setup()
        await setup.model.pressPTT()
        await setup.model.releasePTT()
        #expect(setup.microphone.starts == 0)
        #expect(setup.model.message == nil)
    }

    @Test("the mic gain applies to the transmission")
    func micGain() async {
        let setup = Setup()
        #expect(setup.model.micGain == .none)
        await setup.tuned()
        setup.model.micGain = .high
        #expect(setup.model.micGain == .high)
        await setup.model.pressPTT()
        let samples = [Int16](repeating: 1000, count: KV4P.audioBlockSamples)
        setup.microphone.speak(samples)
        let simulator = setup.simulator
        #expect(await eventually { await simulator.value?.simulator.lastTransmittedAudio != nil })
        var encoder = TXAudioEncoder(gain: .high)
        #expect(await simulator.value?.simulator.lastTransmittedAudio == encoder.encode(samples).first)
    }

    @Test("TX errors are explained")
    func messages() {
        #expect(RadioViewModel.message(for: RadioError.notReady) == "The radio is not ready.")
        #expect(RadioViewModel.message(for: RadioError.frequencyOutOfRange(1)) == "The radio is not ready.")
    }
}
