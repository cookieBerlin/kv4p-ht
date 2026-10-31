import KV4PProtocol
import KV4PSimulator
import KV4PTestSupport
import KV4PTransport
import Testing

@testable import KV4PRadio

/// The view model of the macOS UI, against `RadioController` and the simulator.
@MainActor
@Suite("Radio view model")
struct RadioViewModelTests {
    static let serialDevice = "/dev/cu.usbserial-0001"

    /// Every connection is served by a simulator with `scenario`.
    static func model(_ scenario: Scenario = .ble) -> RadioViewModel {
        RadioViewModel(
            makeController: { _ in
                let clock = ManualClock()
                let transport = SimulatorTransport(simulator: RadioSimulator(scenario: scenario), clock: clock)
                return RadioController(transport: transport, clock: clock)
            },
            serialDevices: { [serialDevice] }
        )
    }

    /// Waits until the model reaches `condition` (snapshots arrive asynchronously).
    func eventually(_ model: RadioViewModel, _ condition: (RadioViewModel) -> Bool) async -> Bool {
        for _ in 0..<100_000 {
            if condition(model) { return true }
            await Task.yield()
        }
        return condition(model)
    }

    func connected(_ scenario: Scenario = .ble) async -> RadioViewModel {
        let model = Self.model(scenario)
        await model.connect()
        #expect(await eventually(model) { $0.isReady && $0.snapshot.isInSync })
        return model
    }

    @Test("connections: simulator, Bluetooth and the USB serial devices")
    func connections() {
        let model = Self.model()
        #expect(model.connections == [.bluetooth, .serial(Self.serialDevice), .simulator])
        #expect(model.selectedConnection == .bluetooth)
        #expect(model.connections.map(\.label) == ["Bluetooth", "USB cu.usbserial-0001", "Simulator"])
        #expect(Set(model.connections.map(\.id)).count == 3)
        #expect(model.statusText == "Not connected")
        #expect(model.canConnect)
        #expect(model.firmwareText == nil)
    }

    @Test("connecting shows the radio and its frequency")
    func connect() async {
        let model = await connected()
        #expect(model.statusText == "Connected")
        #expect(!model.canConnect)
        #expect(model.firmwareText == "Firmware 17 · VHF 134–174 MHz")
        #expect(model.frequencyText == "144.0000")
        #expect(model.isWideBandwidth)
        #expect(model.isHighPower)
        #expect(model.squelch == 0)
        #expect(model.txTone == "None")
        #expect(model.sMeter == 0)
        #expect(model.message == nil)
    }

    @Test("an entered frequency is normalised, clamped and tuned like Android")
    func frequency() async {
        let model = await connected()
        model.frequencyText = "146.52"
        await model.applyFrequency()
        #expect(await eventually(model) { $0.snapshot.deviceState?.radio.freqRx == 146.52 && $0.snapshot.isInSync })
        #expect(model.frequencyText == "146.5200")
        model.frequencyText = "1467"
        await model.applyFrequency()
        #expect(await eventually(model) { $0.snapshot.deviceState?.radio.freqRx == 146.7 })
        model.frequencyText = "200"
        await model.applyFrequency()
        #expect(await eventually(model) { $0.frequencyText == "174.0000" })
        model.frequencyText = "abc"
        await model.applyFrequency()
        #expect(model.message == "\"abc\" is not a frequency.")
        #expect(model.frequencyText == "174.0000")
        model.frequencyText = "inf"
        await model.applyFrequency()
        #expect(model.message == "\"inf\" is not a frequency.")
    }

    @Test("settings are sent to the radio")
    func settings() async {
        let model = await connected()
        model.isWideBandwidth = false
        model.squelch = 4
        model.isHighPower = false
        model.txTone = "88.5"
        model.rxTone = "100"
        model.filters = AudioFilters(preEmphasis: true, highPass: true, lowPass: false)
        #expect(
            await eventually(model) { model in
                guard let radio = model.snapshot.deviceState?.radio, model.snapshot.isInSync else { return false }
                return radio.bandwidth == 0 && radio.squelch == 4 && radio.ctcssTx == 8 && radio.ctcssRx == 12
                    && radio.flags.isSuperset(of: [.filterPre, .filterHigh])
                    && !radio.flags.contains(.highPower) && !radio.flags.contains(.filterLow)
            }
        )
        #expect(model.filters == AudioFilters(preEmphasis: true, highPass: true, lowPass: false))
        #expect(model.rxTone == "100")
        #expect(!model.isWideBandwidth)
        #expect(model.squelch == 4)
        #expect(!model.isHighPower)
        model.isWideBandwidth = true
        #expect(await eventually(model) { $0.snapshot.deviceState?.radio.bandwidth == 1 && $0.isWideBandwidth })
    }

    @Test("settings before connecting are ignored")
    func settingsWhileDisconnected() async {
        let model = Self.model()
        model.squelch = 3
        model.frequencyText = "146.52"
        await model.applyFrequency()
        #expect(model.squelch == 0)
        #expect(model.message == nil)
    }

    @Test("disconnect and reconnect")
    func reconnect() async {
        let model = await connected()
        await model.disconnect()
        #expect(model.statusText == "Not connected")
        #expect(model.canConnect)
        model.selectedConnection = .simulator
        await model.connect()
        #expect(await eventually(model) { $0.isReady })
    }

    @Test(
        "failures are explained",
        arguments: [
            (RadioFailure.helloTimeout, "The radio did not answer. Check that it is on and has firmware 17 or later."),
            (.invalidHello, "The firmware of the radio is too old. Update it to version 17 or later."),
            (.firmwareTooOld(16), "Firmware 16 is too old. Update the radio to version 17 or later."),
            (.radioModuleNotFound, "The SA818 radio module did not respond. Restart the radio."),
            (
                .transport(.bluetoothUnavailable(.unauthorized)),
                "Bluetooth access is not allowed. Allow it in System Settings → Privacy & Security → Bluetooth."
            ),
            (.transport(.bluetoothUnavailable(.poweredOff)), "Bluetooth is off."),
            (.transport(.bluetoothUnavailable(.unsupported)), "Bluetooth is not available."),
            (
                .transport(.serviceNotFound),
                "This device is not a kv4p HT, or its firmware has no Bluetooth LE service."
            ),
            (.transport(.connectionLost), "The connection to the radio was lost."),
            (.transport(.portUnavailable(path: "/dev/cu.x", errno: 16)), "/dev/cu.x cannot be opened."),
            (.transport(.notConnected), "The connection failed."),
        ] as [(RadioFailure, String)]
    )
    func failureMessages(failure: RadioFailure, message: String) {
        #expect(RadioViewModel.message(for: failure) == message)
    }

    @Test("a failed connection shows its message and allows a new attempt")
    func failure() async {
        let model = Self.model(.noRadioModule)
        await model.connect()
        #expect(await eventually(model) { $0.message != nil })
        #expect(model.statusText == "The SA818 radio module did not respond. Restart the radio.")
        #expect(model.canConnect)
    }

    @Test("status while connecting and applying")
    func statusTexts() {
        var snapshot = RadioSnapshot(status: .connecting, desired: HostDesiredState(), isInSync: false)
        #expect(RadioViewModel.statusText(for: snapshot) == "Connecting…")
        snapshot.status = .waitingForHello
        #expect(RadioViewModel.statusText(for: snapshot) == "Waiting for the radio…")
        snapshot.status = .ready
        #expect(RadioViewModel.statusText(for: snapshot) == "Connected, applying settings…")
    }

    @Test("an invalid stored tone is shown as no tone")
    func invalidStoredTone() async {
        var scenario = Scenario.ble
        scenario.storedState = RadioState(
            flags: [.radioConfigValid],
            bandwidth: 1,
            freqTx: 146,
            freqRx: 146,
            ctcssTx: 99
        )
        let model = await connected(scenario)
        #expect(model.txTone == "None")
    }

    @Test("UHF firmware text")
    func uhf() async {
        let model = await connected(.uhf)
        #expect(model.firmwareText == "Firmware 17 · UHF 400–480 MHz")
    }
}
