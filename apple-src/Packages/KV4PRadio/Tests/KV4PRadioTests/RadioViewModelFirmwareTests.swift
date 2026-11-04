import KV4PFlasher
import KV4PSimulator
import KV4PTestSupport
import KV4PTransport
import Synchronization
import Testing

@testable import KV4PRadio

/// A flasher that reports `events` and then fails with `error`, if any.
final class FakeFirmwareFlasher: FirmwareFlashing {
    private let flashed = Mutex<[String]>([])
    private let written = Mutex<[FirmwareImages]>([])
    private let events: [FlashEvent]
    private let error: FlashError?

    init(events: [FlashEvent] = [.connected, .progress(50), .progress(100)], error: FlashError? = nil) {
        self.events = events
        self.error = error
    }

    var paths: [String] { flashed.withLock { $0 } }
    var images: [FirmwareImages] { written.withLock { $0 } }

    func flash(
        _ images: FirmwareImages,
        serialPath: String,
        events report: @Sendable (FlashEvent) -> Void
    ) async throws(FlashError) {
        flashed.withLock { $0.append(serialPath) }
        written.withLock { $0.append(images) }
        events.forEach(report)
        if let error { throw error }
    }
}

/// `MainActivity.showVersionSnackbar` and `startFirmwareActivity`: firmware updates over USB (macOS).
@MainActor
@Suite("Radio view model firmware")
struct RadioViewModelFirmwareTests {
    static let path = RadioViewModelTests.serialDevice
    static let forThisApp = FirmwareChoice(
        edition: .forThisApp,
        images: FirmwareImages(bootloader: [1], partitions: [2], bootApp0: [3], app: [9]),
        sha256: "aa11",
        build: .init(commit: "a7c6b4d4790a", built: "2026-10-17 07:52 UTC")
    )
    static let forAndroid = FirmwareChoice(
        edition: .forAndroid,
        images: FirmwareImages(bootloader: [1], partitions: [2], bootApp0: [3], app: [4]),
        sha256: "bb22"
    )
    static let choices = [forThisApp, forAndroid]

    static func model(_ scenario: Scenario = .ble, flasher: FakeFirmwareFlasher?) -> RadioViewModel {
        let model = RadioViewModel(
            makeController: { _, rxAudio in
                let clock = ManualClock()
                let transport = SimulatorTransport(simulator: RadioSimulator(scenario: scenario), clock: clock)
                return RadioController(transport: transport, clock: clock, rxAudio: rxAudio)
            },
            serialDevices: { [path] },
            firmware: flasher,
            firmwareChoices: flasher == nil ? [] : choices
        )
        model.selectedConnection = .serial(path)
        return model
    }

    @Test("updates are offered for a USB radio when the app has a flasher and firmware")
    func offered() {
        #expect(!Self.model(flasher: nil).canUpdateFirmware)
        let empty = RadioViewModel(
            makeController: { _, rxAudio in RadioController(transport: SimulatorTransport(), rxAudio: rxAudio) },
            serialDevices: { [Self.path] },
            firmware: FakeFirmwareFlasher()
        )
        empty.selectedConnection = .serial(Self.path)
        #expect(!empty.canUpdateFirmware)
        let model = Self.model(flasher: FakeFirmwareFlasher())
        #expect(model.canUpdateFirmware)
        #expect(model.firmwareUpdate == .idle)
        model.selectedConnection = .bluetooth
        #expect(!model.canUpdateFirmware)
    }

    @Test("the firmware for Android is written, and the app stays disconnected and says so")
    func updateForAndroid() async {
        let flasher = FakeFirmwareFlasher()
        let model = Self.model(flasher: flasher)
        await model.connect()
        #expect(await RadioViewModelTests.eventually(model) { $0.isReady })
        await model.updateFirmware(to: Self.forAndroid)
        #expect(flasher.images == [Self.forAndroid.images])
        #expect(model.firmwareUpdate == .finishedForAndroid)
        #expect(!model.firmwareUpdate.isRunning)
        #expect(!model.isReady)
    }

    @Test("an update disconnects, flashes with progress and reconnects")
    func update() async {
        let flasher = FakeFirmwareFlasher()
        let model = Self.model(flasher: flasher)
        await model.connect()
        #expect(await RadioViewModelTests.eventually(model) { $0.isReady })
        var states: [RadioViewModel.FirmwareUpdate] = []
        let watcher = Task { @MainActor in
            while !Task.isCancelled {
                if states.last != model.firmwareUpdate { states.append(model.firmwareUpdate) }
                await Task.yield()
            }
        }
        await model.updateFirmware(to: Self.forThisApp)
        #expect(flasher.paths == [Self.path])
        #expect(flasher.images == [Self.forThisApp.images])
        #expect(model.firmwareUpdate == .finished)
        #expect(await RadioViewModelTests.eventually(model) { $0.isReady })
        watcher.cancel()
        #expect(states.first == .idle)
        #expect(states.last == .finished)
        #expect(model.firmwareUpdate.isRunning == false)
        #expect(RadioViewModel.FirmwareUpdate.connecting.isRunning)
        #expect(RadioViewModel.FirmwareUpdate.flashing(percent: 5).isRunning)
    }

    @Test("the status line reports the update, and the next connection ends a message about it")
    func statusLine() async {
        let model = Self.model(flasher: FakeFirmwareFlasher())
        await model.updateFirmware(to: Self.forAndroid)
        #expect(model.statusText == "Firmware updated and verified. The radio is now set up for the Android app.")
        #expect(!model.isStatusFailure)
        await model.connect()
        #expect(model.firmwareUpdate == .idle)
        #expect(model.statusText != "Firmware updated and verified. The radio is now set up for the Android app.")
        let failing = Self.model(flasher: FakeFirmwareFlasher(error: .noAnswer))
        #expect(!failing.isStatusFailure)
        await failing.updateFirmware(to: Self.forThisApp)
        #expect(failing.statusText == RadioViewModel.message(for: FlashError.noAnswer))
        #expect(failing.isStatusFailure)
        await failing.connect()
        #expect(failing.firmwareUpdate == .idle)
    }

    @Test("while the update runs, the status line shows its progress, also after a failed connection")
    func statusLineRunning() async {
        var scenario = Scenario.ble
        scenario.firmwareVersion = 16
        let model = Self.model(scenario, flasher: FakeFirmwareFlasher())
        await model.connect()
        #expect(await RadioViewModelTests.eventually(model) { $0.isStatusFailure })
        var texts: [String] = []
        var failures: [Bool] = []
        let watcher = Task { @MainActor in
            while !Task.isCancelled {
                if model.firmwareUpdate.isRunning {
                    texts.append(model.statusText)
                    failures.append(model.isStatusFailure)
                }
                await Task.yield()
            }
        }
        #expect(!model.statusText.isEmpty)
        await model.updateFirmware(to: Self.forThisApp)
        watcher.cancel()
        #expect(texts.allSatisfy { $0 == "Starting the bootloader…" || $0.hasPrefix("Updating firmware… ") })
        #expect(failures.allSatisfy { !$0 })
        #expect(RadioViewModel.statusLine(for: .connecting) == "Starting the bootloader…")
        #expect(RadioViewModel.statusLine(for: .flashing(percent: 40)) == "Updating firmware… 40 %")
        #expect(RadioViewModel.statusLine(for: .idle) == nil)
        #expect(RadioViewModel.statusLine(for: .finished) == nil)
    }

    @Test("with a firmware problem, the Mac offers the way to the settings, and asks for USB if needed")
    func wayToSettings() async {
        let model = Self.model(.androidFirmware, flasher: FakeFirmwareFlasher())
        #expect(!model.offersFirmwareSettings)
        await model.connect()
        #expect(await RadioViewModelTests.eventually(model) { $0.offersFirmwareSettings })
        #expect(model.firmwareUpdateHint == nil)
        model.selectedConnection = .bluetooth
        #expect(model.firmwareUpdateHint == "Connect the radio by USB and choose it under Radio.")
        #expect(!model.isFirmwareSettingsRequested)
        model.requestFirmwareSettings()
        #expect(model.isFirmwareSettingsRequested)
        model.firmwareSettingsShown()
        #expect(!model.isFirmwareSettingsRequested)
        let phone = Self.model(.androidFirmware, flasher: nil)
        await phone.connect()
        #expect(await RadioViewModelTests.eventually(phone) { $0.needsFirmwareUpdateElsewhere })
        #expect(!phone.offersFirmwareSettings)
        #expect(phone.firmwareUpdateHint == nil)
    }

    @Test("a failed update says why and leaves the radio disconnected")
    func failed() async {
        let model = Self.model(flasher: FakeFirmwareFlasher(events: [.connected, .progress(40)], error: .noAnswer))
        await model.updateFirmware(to: Self.forThisApp)
        #expect(model.firmwareUpdate == .failed(RadioViewModel.message(for: FlashError.noAnswer)))
        #expect(!model.isReady)
    }

    @Test("a radio with old or missing firmware is outdated")
    func outdated() async {
        var scenario = Scenario.ble
        scenario.firmwareVersion = 16
        let model = Self.model(scenario, flasher: FakeFirmwareFlasher())
        #expect(!model.isFirmwareOutdated)
        await model.connect()
        #expect(await RadioViewModelTests.eventually(model) { $0.isFirmwareOutdated })
        #expect(model.canUpdateFirmware)
        var missing = Scenario.ble
        missing.faults.omitsHello = true
        let silent = RadioViewModel(
            makeController: { _, rxAudio in
                let clock = ManualClock()
                let transport = SimulatorTransport(simulator: RadioSimulator(scenario: missing), clock: clock)
                let controller = RadioController(
                    transport: transport,
                    clock: clock,
                    helloTimeout: .zero,
                    rxAudio: rxAudio
                )
                return controller
            },
            serialDevices: { [Self.path] }
        )
        await silent.connect()
        #expect(await RadioViewModelTests.eventually(silent) { $0.isFirmwareOutdated })
    }

    @Test("the firmware for Android counts as outdated and can be updated")
    func android() async {
        let model = Self.model(.androidFirmware, flasher: FakeFirmwareFlasher())
        await model.connect()
        #expect(await RadioViewModelTests.eventually(model) { $0.isFirmwareOutdated })
        #expect(model.canUpdateFirmware)
        #expect(!model.needsFirmwareUpdateElsewhere)
    }

    @Test("without a flasher (iOS), outdated firmware and firmware without BLE point elsewhere")
    func elsewhere() async {
        var scenario = Scenario.ble
        scenario.firmwareVersion = 16
        let model = Self.model(scenario, flasher: nil)
        model.selectedConnection = .bluetooth
        #expect(!model.needsFirmwareUpdateElsewhere)
        await model.connect()
        #expect(await RadioViewModelTests.eventually(model) { $0.isFirmwareOutdated })
        #expect(model.needsFirmwareUpdateElsewhere)
        let flashing = Self.model(scenario, flasher: FakeFirmwareFlasher())
        await flashing.connect()
        #expect(await RadioViewModelTests.eventually(flashing) { $0.isFirmwareOutdated })
        #expect(!flashing.needsFirmwareUpdateElsewhere)
        #expect(
            FirmwareHelp.manualAddress
                == "https://github.com/cookieBerlin/kv4p-ht/blob/main/docs/apple/manual.md#firmware-updates"
        )
    }

    @Test(
        "flash errors explain what to do",
        arguments: [
            FlashError.noAnswer, .timeout(opcode: 2), .commandFailed(opcode: 3, error: 5), .stubNotStarted,
            .unsupportedChip(9), .verifyFailed(offset: 0x1000), .port(.connectionLost),
        ]
    )
    func messages(error: FlashError) {
        #expect(!RadioViewModel.message(for: error).isEmpty)
    }
}
