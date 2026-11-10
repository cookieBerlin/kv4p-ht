import KV4PAPRS
import KV4PSimulator
import KV4PTestSupport
import Testing

@testable import KV4PRadio

/// Configuring the simulator from the settings (ADR-0041).
@MainActor
@Suite("Radio view model: simulator")
struct RadioViewModelSimulatorTests {
    @MainActor
    final class Setup {
        let radio: SimulatorRadio<ManualClock>
        let store: MemorySettingsStore
        let model: RadioViewModel

        /// `mac`: with a flasher and firmware; otherwise over Bluetooth only, as on iOS.
        init(store: MemorySettingsStore = MemorySettingsStore(), mac: Bool = false, flasher: FakeFirmwareFlasher? = nil)
        {
            self.store = store
            let radio = SimulatorRadio(clock: ManualClock(), isOverBluetooth: !mac)
            self.radio = radio
            model = RadioViewModel(
                makeController: { _, rxAudio in
                    RadioController(transport: radio.makeTransport(), clock: ManualClock(), rxAudio: rxAudio)
                },
                serialDevices: { [] },
                firmware: mac ? (flasher ?? FakeFirmwareFlasher()) : nil,
                firmwareChoices: mac ? RadioViewModelFirmwareTests.choices : [],
                settings: store,
                simulator: radio,
                simulatedFlashStep: .zero
            )
            model.callsign = "N0CALL"
        }

        func connect() async {
            model.selectedConnection = .simulator
            await model.connect()
            #expect(await RadioViewModelTests.eventually(model) { $0.isReady && $0.snapshot.isInSync })
        }
    }

    @Test("the section shows only while the simulator is the chosen radio")
    func section() {
        let setup = Setup()
        #expect(!setup.model.canConfigureSimulator)
        setup.model.selectedConnection = .simulator
        #expect(setup.model.canConfigureSimulator)
        let plain = RadioViewModelTests.model()
        plain.selectedConnection = .simulator
        #expect(!plain.canConfigureSimulator)
    }

    @Test("the settings are saved and restored, and reach the simulator")
    func saved() {
        let setup = Setup()
        setup.model.simulatorSettings.band = .uhf
        #expect(setup.store.settings.simulator.band == .uhf)
        #expect(setup.radio.settings.band == .uhf)
        let restored = Setup(store: setup.store)
        #expect(restored.model.simulatorSettings.band == .uhf)
        #expect(restored.radio.settings.band == .uhf)
    }

    @Test("the next connection uses the settings")
    func nextConnection() async {
        let setup = Setup()
        setup.model.simulatorSettings.band = .uhf
        await setup.connect()
        #expect(setup.model.firmwareText?.contains("UHF") == true)
    }

    @Test("the signal opens the squelch and ends with the connection")
    func signal() async {
        let setup = Setup()
        #expect(!setup.model.canSimulateSignal)
        await setup.connect()
        #expect(setup.model.canSimulateSignal)
        setup.model.simulatedSignal = .s9
        #expect(await RadioViewModelTests.eventually(setup.model) { $0.isReceiving })
        setup.model.simulatedSignal = nil
        #expect(await RadioViewModelTests.eventually(setup.model) { !$0.isReceiving })
        setup.model.simulatedSignal = .s3
        await setup.model.disconnect()
        #expect(setup.model.simulatedSignal == nil)
    }

    @Test("the simulator starts on a frequency it may transmit on")
    func startFrequency() async {
        let setup = Setup()
        await setup.connect()
        #expect(setup.model.frequencyText == "145.5000")
        #expect(setup.model.canTransmit)
        #expect(setup.model.transmitBlockedText == nil)
    }

    @Test("at the band edge, the message names the allowed range for the bandwidth")
    func blockedText() async {
        let setup = Setup()
        #expect(setup.model.transmitBlockedText == nil)
        await setup.connect()
        setup.model.frequencyText = "144"
        await setup.model.applyFrequency()
        #expect(await RadioViewModelTests.eventually(setup.model) { !$0.canTransmit })
        #expect(
            setup.model.transmitBlockedText
                == "Can't transmit here: with 25 kHz, the allowed range is 144.0125–147.9875 MHz."
        )
        setup.model.isWideBandwidth = false
        #expect(
            await RadioViewModelTests.eventually(setup.model) {
                $0.transmitBlockedText
                    == "Can't transmit here: with 12.5 kHz, the allowed range is 144.00625–147.99375 MHz."
            }
        )
    }

    /// A simulator that records the signals.
    @MainActor
    final class FakeSimulator: SimulatorControlling {
        var settings = SimulatorSettings()
        private(set) var signals: [SimulatedSignal?] = []

        func setSignal(_ signal: SimulatedSignal?) async {
            signals.append(signal)
        }

        func loseConnection() async {}

        func hear(_ frame: [UInt8]) async {}
    }

    static func rampModel(_ fake: FakeSimulator, step: Duration) -> RadioViewModel {
        RadioViewModel(
            makeController: { _, rxAudio in
                RadioController(
                    transport: SimulatorTransport(clock: ManualClock()),
                    clock: ManualClock(),
                    rxAudio: rxAudio
                )
            },
            serialDevices: { [] },
            simulator: fake,
            simulatedSignalStep: step
        )
    }

    @Test("the ramp plays every strength up and down, then ends without a signal")
    func ramp() async {
        let fake = FakeSimulator()
        let model = Self.rampModel(fake, step: .zero)
        #expect(!model.isSignalRampRunning)
        model.toggleSignalRamp()
        #expect(model.isSignalRampRunning)
        #expect(await KV4PTestSupport.eventually { !model.isSignalRampRunning })
        #expect(await KV4PTestSupport.eventually { fake.signals.last == .some(nil) })
        #expect(model.simulatedSignal == nil)
        #expect(fake.signals.dropLast().map { $0 } == SimulatedSignal.ramp.map { $0 })
    }

    @Test("the ramp stops on request and with the connection")
    func rampStops() async {
        let fake = FakeSimulator()
        let model = Self.rampModel(fake, step: .seconds(60))
        model.toggleSignalRamp()
        #expect(await KV4PTestSupport.eventually { model.simulatedSignal == .s0 })
        model.toggleSignalRamp()
        #expect(!model.isSignalRampRunning)
        #expect(model.simulatedSignal == nil)
        model.toggleSignalRamp()
        #expect(await KV4PTestSupport.eventually { model.simulatedSignal == .s0 })
        await model.disconnect()
        #expect(!model.isSignalRampRunning)
        #expect(model.simulatedSignal == nil)
    }

    @Test("each strength is named like the S-meter shows it", arguments: SimulatedSignal.allCases)
    func strengthLabels(signal: SimulatedSignal) {
        #expect(signal.label == RadioViewModel.sMeterText(for: signal.rawValue))
    }

    @Test("without a simulator, there is no signal to simulate")
    func noSimulator() async {
        let plain = RadioViewModelTests.model()
        plain.selectedConnection = .simulator
        await plain.connect()
        #expect(await RadioViewModelTests.eventually(plain) { $0.isReady })
        #expect(!plain.canSimulateSignal)
        plain.simulatedSignal = .s9
        plain.loseSimulatedConnection()
        plain.simulatePacket(.status)
        #expect(plain.isReady)
        #expect(plain.aprsEvents.isEmpty)
    }

    @Test("a real radio cannot use them")
    func realRadio() async {
        let setup = Setup()
        await setup.model.connect()
        #expect(await RadioViewModelTests.eventually(setup.model) { $0.isReady })
        #expect(!setup.model.canSimulateSignal)
    }

    @Test("on the Mac the simulator offers a firmware update; on iOS it does not, as with a real radio")
    func offersUpdate() {
        let mac = Setup(mac: true)
        mac.model.selectedConnection = .simulator
        #expect(mac.model.canUpdateFirmware)
        let phone = Setup()
        phone.model.selectedConnection = .simulator
        #expect(!phone.model.canUpdateFirmware)
        let plain = RadioViewModelTests.model()
        plain.selectedConnection = .simulator
        #expect(!plain.canUpdateFirmware)
    }

    @Test(
        "on the Mac, too old firmware offers the update, and the firmware for this app fixes it; no real radio is written"
    )
    func update() async {
        let flasher = FakeFirmwareFlasher()
        let setup = Setup(mac: true, flasher: flasher)
        setup.model.simulatorSettings.firmware = .tooOld
        setup.model.selectedConnection = .simulator
        await setup.model.connect()
        #expect(await RadioViewModelTests.eventually(setup.model) { $0.isFirmwareOutdated })
        #expect(!setup.model.needsFirmwareUpdateElsewhere)
        #expect(setup.model.canUpdateFirmware)
        await setup.model.updateFirmware(to: RadioViewModelFirmwareTests.forThisApp)
        #expect(setup.model.firmwareUpdate == .finished)
        #expect(setup.model.simulatorSettings.firmware == .current)
        #expect(await RadioViewModelTests.eventually(setup.model) { $0.isReady })
        #expect(flasher.paths.isEmpty)
    }

    @Test("on the Mac, the firmware for Android reaches the simulator, and the app stays disconnected from it")
    func updateForAndroid() async {
        let setup = Setup(mac: true)
        setup.model.selectedConnection = .simulator
        await setup.model.updateFirmware(to: RadioViewModelFirmwareTests.forAndroid)
        #expect(setup.model.firmwareUpdate == .finishedForAndroid)
        #expect(setup.model.simulatorSettings.firmware == .android)
        #expect(!setup.model.isReady)
        await setup.model.connect()
        #expect(await RadioViewModelTests.eventually(setup.model) { $0.isFirmwareOutdated })
        #expect(setup.model.statusText == RadioViewModel.message(for: RadioFailure.firmwareForAndroid))
    }

    @Test(
        "on iOS, firmware without BLE fails the connection and only shows messages, as with a real radio",
        arguments: [SimulatedFirmware.android, .tooOld]
    )
    func messagesOnly(firmware: SimulatedFirmware) async {
        let setup = Setup()
        setup.model.simulatorSettings.firmware = firmware
        setup.model.selectedConnection = .simulator
        #expect(!setup.model.needsFirmwareUpdateElsewhere)
        await setup.model.connect()
        #expect(await RadioViewModelTests.eventually(setup.model) { $0.needsFirmwareUpdateElsewhere })
        #expect(setup.model.statusText == RadioViewModel.message(for: RadioFailure.transport(.serviceNotFound)))
        #expect(!setup.model.canUpdateFirmware)
        await setup.model.updateFirmware(to: RadioViewModelFirmwareTests.forThisApp)
        #expect(setup.model.firmwareUpdate == .idle)
    }

    @Test("losing the connection is reported as a failure")
    func lose() async {
        let setup = Setup()
        await setup.connect()
        setup.model.loseSimulatedConnection()
        #expect(await RadioViewModelTests.eventually(setup.model) { $0.hasFailed })
        #expect(setup.model.statusText == "The connection to the radio was lost.")
    }

    @Test(
        "each test packet shows as its type",
        arguments: [
            (SimulatedPacket.message, APRSEvent.Kind.message),
            (.position, .position),
            (.object, .object),
            (.weather, .weather),
            (.status, .status),
        ]
    )
    func packets(packet: SimulatedPacket, kind: APRSEvent.Kind) async {
        let setup = Setup()
        await setup.connect()
        setup.model.simulatePacket(packet)
        #expect(await RadioViewModelTests.eventually(setup.model) { $0.aprsEvents.first?.kind == kind })
        #expect(!packet.label.isEmpty)
    }

    @Test("a test message goes to the user's callsign, or to a placeholder")
    func recipient() async {
        let setup = Setup()
        setup.model.callsign = "N2CALL"
        await setup.connect()
        setup.model.simulatePacket(.message)
        #expect(await RadioViewModelTests.eventually(setup.model) { $0.aprsEvents.first?.toCallsign == "N2CALL" })
        let unnamed = Setup()
        await unnamed.connect()
        unnamed.model.simulatePacket(.message)
        #expect(await RadioViewModelTests.eventually(unnamed.model) { $0.aprsEvents.first?.toCallsign == "N0CALL" })
    }

    @Test("the simulator stays the chosen radio after a restart")
    func staysChosen() {
        let setup = Setup()
        setup.model.selectedConnection = .simulator
        #expect(setup.store.settings.isSimulatorChosen)
        #expect(Setup(store: setup.store).model.selectedConnection == .simulator)
        setup.model.selectedConnection = .bluetooth
        #expect(!setup.store.settings.isSimulatorChosen)
        #expect(Setup(store: setup.store).model.selectedConnection == .bluetooth)
    }

    @Test("every connection to the simulator starts with squelch 3, like its fixed frequency")
    func startsWithSquelch() async {
        let setup = Setup()
        await setup.connect()
        #expect(setup.model.squelch == 3)
        setup.model.squelch = 5
        #expect(await RadioViewModelTests.eventually(setup.model) { $0.squelch == 5 && $0.snapshot.isInSync })
        await setup.model.disconnect()
        await setup.connect()
        #expect(setup.model.squelch == 3)
    }
}
