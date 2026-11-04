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
