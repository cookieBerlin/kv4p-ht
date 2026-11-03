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
        let radio = SimulatorRadio(clock: ManualClock())
        let store: MemorySettingsStore
        let model: RadioViewModel

        init(store: MemorySettingsStore = MemorySettingsStore()) {
            self.store = store
            let radio = radio
            model = RadioViewModel(
                makeController: { _, rxAudio in
                    RadioController(transport: radio.makeTransport(), clock: ManualClock(), rxAudio: rxAudio)
                },
                serialDevices: { [] },
                settings: store,
                simulator: radio,
                simulatedFlashStep: .zero
            )
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
        #expect(setup.model.bandText == "UHF")
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

    @Test("the simulator offers a firmware update, also without a flasher")
    func offersUpdate() {
        let setup = Setup()
        #expect(!setup.model.canUpdateFirmware)
        setup.model.selectedConnection = .simulator
        #expect(setup.model.canUpdateFirmware)
        let plain = RadioViewModelTests.model()
        plain.selectedConnection = .simulator
        #expect(!plain.canUpdateFirmware)
    }

    @Test("too old firmware offers the update, not the web flasher, and the update fixes it")
    func update() async {
        let setup = Setup()
        setup.model.simulatorSettings.hasCurrentFirmware = false
        setup.model.selectedConnection = .simulator
        await setup.model.connect()
        #expect(await RadioViewModelTests.eventually(setup.model) { $0.isFirmwareOutdated })
        #expect(!setup.model.isWebFlasherNeeded)
        #expect(setup.model.canUpdateFirmware)
        await setup.model.updateFirmware()
        #expect(setup.model.firmwareUpdate == .finished)
        #expect(setup.model.simulatorSettings.hasCurrentFirmware)
        #expect(await RadioViewModelTests.eventually(setup.model) { $0.isReady })
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
}
