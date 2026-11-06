import Foundation
import KV4PAPRS
import KV4PAudio
import KV4PFlasher
import KV4PPersistence
import KV4PRadio
import KV4PSimulator
import KV4PTransport

/// Composition root: wires the OS adapters to the radio stack. All behaviour lives in the packages.
@MainActor
enum Composition {
    /// The simulated radio, which the settings configure.
    private static let simulator = SimulatorRadio(clock: ContinuousClock(), isOverBluetooth: isOverBluetoothOnly)

    /// iPhone and iPad reach a radio over Bluetooth only, so the simulator behaves like such a radio there.
    private static var isOverBluetoothOnly: Bool {
        #if os(iOS)
            true
        #else
            false
        #endif
    }

    /// The firmwares of the app's bundle, which only the Mac has (ADR-0049).
    private static let firmwareChoices = Bundle.main.resourceURL.map(FirmwareChoice.bundled(in:)) ?? []

    /// The log and crash data of this device (ADR-0059).
    private static let diagnosticsFolder = URL.applicationSupportDirectory.appending(path: "Diagnostics")
    private static let diagnostics = DiagnosticLog(
        store: LogFile(folder: diagnosticsFolder.appending(path: "Log")),
        now: RadioViewModel.systemTimeMs
    )
    private static var crashReports: MetricKitCrashReports?
    private static var cloudKitFailures: Task<Void, Never>?
    private static var notificationOpener: NotificationOpener?

    /// Started with this, the app shows placeholder content on the simulator and keeps nothing (ADR-0062).
    static let demoArgument = "-uitest-demo"

    static func makeViewModel() -> RadioViewModel {
        if ProcessInfo.processInfo.arguments.contains(demoArgument) {
            return makeDemoViewModel()
        }
        diagnostics.log(.info, .app, "Started: \(appVersion) on \(ProblemReport.Environment.current.system)")
        cloudKitFailures = CloudKitSyncEvents.logFailures(to: diagnostics)
        let model = RadioViewModel(
            makeController: {
                RadioController(
                    transport: transport(for: $0),
                    rxAudio: $1,
                    microphone: AVAudioEngineInput(diagnostics: diagnostics),
                    diagnostics: diagnostics
                )
            },
            serialDevices: serialDevices,
            audioOutput: AVAudioEngineOutput(diagnostics: diagnostics),
            audioSession: audioSession(),
            otherAppsMute: otherAppsMute(),
            memories: memoryRepository(),
            location: CoreLocationProvider(diagnostics: diagnostics),
            backgroundLocation: backgroundLocation(),
            internet: APRSISClient(
                software: "kv4p-ht",
                version: appVersion,
                connector: NetworkLineConnector(),
                diagnostics: diagnostics
            ),
            firmware: firmwareFlasher(),
            firmwareChoices: firmwareChoices,
            aprsHistory: aprsHistory(),
            settings: settingsStore(),
            syncedSettings: UbiquitousSettingsStore(),
            bluetoothScanner: BLEScanner { CoreBluetoothCentral() },
            failureAlerts: PlatformFailureAlerts(diagnostics: diagnostics),
            messageNotifier: SystemMessageNotifier(diagnostics: diagnostics),
            permissions: SystemPermissions(),
            diagnostics: diagnostics,
            crashReports: CrashReportStore(folder: diagnosticsFolder.appending(path: "Crashes")),
            simulator: simulator
        )
        crashReports = MetricKitCrashReports(model: model)
        notificationOpener = NotificationOpener(model: model)
        return model
    }

    /// iOS shares the audio hardware between apps through a session; macOS has none.
    private static func audioSession() -> (any AudioSession)? {
        #if os(iOS)
            AVAudioSessionAdapter(diagnostics: diagnostics)
        #else
            nil
        #endif
    }

    /// Only iOS limits the location in the background.
    private static func backgroundLocation() -> (any BackgroundLocationKeeping)? {
        #if os(iOS)
            CoreLocationBackgroundSession()
        #else
            nil
        #endif
    }

    /// The Mac has no session, but a tap can silence other apps.
    private static func otherAppsMute() -> (any OtherAudioSwitching)? {
        #if os(macOS)
            CoreAudioOtherAppsMute(diagnostics: diagnostics)
        #else
            nil
        #endif
    }

    /// The app settings in the user defaults; the callsign, kept on its own before, moves into them once.
    private static func settingsStore() -> any SettingsStore {
        let store = UserDefaultsSettingsStore()
        if store.load() == nil, let callsign = UserDefaults.standard.string(forKey: "aprsCallsign") {
            var settings = AppSettings()
            settings.callsign = callsign
            if let data = try? settings.encoded() { store.save(data) }
        }
        return store
    }

    /// `CFBundleShortVersionString`, sent in the APRS-IS login.
    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    /// For the accessibility audit: the simulator, stores in memory only, settings of their own that start anew, no
    /// iCloud, no notifications and no permission asked, so that nothing in it depends on the device.
    private static func makeDemoViewModel() -> RadioViewModel {
        let defaults = UserDefaults(suiteName: "uitest-demo") ?? .standard
        defaults.removePersistentDomain(forName: "uitest-demo")
        var settings = AppSettings()
        settings.callsign = "N0CALL"
        settings.isSimulatorChosen = true
        settings.isSettingsSyncEnabled = false
        settings.notifiesAboutMessages = false
        let store = UserDefaultsSettingsStore(defaults: defaults)
        if let data = try? settings.encoded() { store.save(data) }
        let model = RadioViewModel(
            makeController: { _, rxAudio in RadioController(transport: simulator.makeTransport(), rxAudio: rxAudio) },
            serialDevices: { [] },
            memories: try? SwiftDataMemoryRepository.inMemory(),
            aprsHistory: try? SwiftDataAPRSHistory.inMemory(),
            settings: store,
            simulator: simulator
        )
        Task {
            await model.loadDemoContent()
            await model.connect()
        }
        return model
    }

    /// The memories live in the app's Application Support folder; without it the app runs without memories. They sync
    /// if the user wants that at this start (ADR-0052); if the store does not open with iCloud, it does without.
    private static func memoryRepository() -> (any MemoryRepository)? {
        let folder = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "Memories.store")
        let syncs = AppSettings(data: UserDefaultsSettingsStore().load()).isSettingsSyncEnabled
        do {
            return try SwiftDataMemoryRepository(storeURL: url, syncs: syncs)
        } catch {
            diagnostics.log(.error, .storage, "Memories with sync: \(DiagnosticLog.describe(error))")
        }
        do {
            return try SwiftDataMemoryRepository(storeURL: url, syncs: false)
        } catch {
            diagnostics.log(.error, .storage, "Memories: \(DiagnosticLog.describe(error))")
            return nil
        }
    }

    /// The APRS packets, in a store of their own that never syncs (ADR-0057).
    private static func aprsHistory() -> (any APRSHistoryStoring)? {
        let folder = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            return try SwiftDataAPRSHistory.inFolder(folder)
        } catch {
            diagnostics.log(.error, .storage, "APRS history: \(DiagnosticLog.describe(error))")
            return nil
        }
    }

    private static func transport(for connection: RadioViewModel.Connection) -> any RadioTransport {
        switch connection {
        case .bluetooth:
            return BLETransport(central: CoreBluetoothCentral(diagnostics: diagnostics))
        case .bluetoothDevice(let device):
            return BLETransport(central: CoreBluetoothCentral(diagnostics: diagnostics), peripheral: device.id)
        case .serial(let path):
            return serialTransport(path)
        case .simulator:
            return simulator.makeTransport()
        }
    }

    #if os(macOS)
        /// Flashing keeps the Mac awake.
        private static func firmwareFlasher() -> (any FirmwareFlashing)? {
            guard !firmwareChoices.isEmpty else {
                diagnostics.log(.error, .firmware, "The app has no firmware to offer")
                return nil
            }
            guard let stub = try? FlasherStub.esp32() else {
                diagnostics.log(.error, .firmware, "The flasher stub could not be read")
                return nil
            }
            let flasher = FirmwareFlasher(stub: stub, clock: ContinuousClock()) {
                SerialBootloaderPort(port: POSIXSerialPort(path: $0), clock: ContinuousClock())
            }
            return AwakeFirmwareFlasher(flasher: flasher)
        }

        /// The radio restarts on connect so that it sends HELLO.
        private static func serialTransport(_ path: String) -> any RadioTransport {
            SerialTransport(port: POSIXSerialPort(path: path), resetOnConnect: true)
        }

        private static func serialDevices() -> [String] {
            POSIXSerialPort.devices()
        }
    #else
        private static func firmwareFlasher() -> (any FirmwareFlashing)? {
            nil
        }

        private static func serialTransport(_ path: String) -> any RadioTransport {
            SimulatorTransport()
        }

        private static func serialDevices() -> [String] {
            []
        }
    #endif
}

/// Keeps the Mac from sleeping while the firmware is written.
private struct AwakeFirmwareFlasher: FirmwareFlashing {
    let flasher: any FirmwareFlashing

    func flash(
        _ images: FirmwareImages,
        serialPath: String,
        events: @Sendable (FlashEvent) -> Void
    ) async throws(FlashError) {
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Updating the radio's firmware"
        )
        defer { ProcessInfo.processInfo.endActivity(activity) }
        try await flasher.flash(images, serialPath: serialPath, events: events)
    }
}
