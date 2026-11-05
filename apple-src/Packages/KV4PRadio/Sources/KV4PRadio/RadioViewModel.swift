import Foundation
import KV4PAPRS
import KV4PAudio
import KV4PFlasher
import KV4PPersistence
import KV4PProtocol
import KV4PSimulator
import KV4PTransport
import Observation

/// What the view model needs from `RadioController`, independent of its clock.
public protocol RadioControlling: Actor {
    nonisolated var snapshots: AsyncStream<RadioSnapshot> { get }
    nonisolated var receivedFrames: AsyncStream<[UInt8]> { get }
    func connect() async
    func disconnect() async
    func tune(rx: Float, tx: Float, memoryId: Int32) throws(RadioError)
    func update(_ changes: @Sendable (inout DesiredStateController) -> Void)
    var snapshot: RadioSnapshot { get }
    func setMicGain(_ gain: MicGain)
    func setTXLimits(_ limits: TXLimits)
    func prepareMicrophone()
    func setFreeDV(_ on: Bool)
    func startTransmitting() async throws(RadioError)
    func stopTransmitting()
    func tune(to memory: ChannelMemory) throws(RadioError)
    func transmitAX25(_ frame: [UInt8], frequency: Float) throws(RadioError)
    func sendAccessTone(_ tone: AccessTone) async throws(RadioError) -> AccessToneResult
    func startScan(_ memories: [ChannelMemory]) throws(RadioError)
    func stopScan()
}

extension RadioController: RadioControlling {}

/// Pre-emphasis and the high- and low-pass audio filters of the SA818.
public struct AudioFilters: Equatable, Sendable {
    public var preEmphasis: Bool
    public var highPass: Bool
    public var lowPass: Bool

    public init(preEmphasis: Bool, highPass: Bool, lowPass: Bool) {
        self.preEmphasis = preEmphasis
        self.highPass = highPass
        self.lowPass = lowPass
    }
}

/// What a bar of the S-meter stands for; red is only for the one real problem, overload (ADR-0040).
public enum SMeterZone: Sendable {
    case weak, normal, strong, overload

    /// `bar` counts from 0: bar 0 lights at S1, and the last one at overload.
    public init(bar: Int) {
        switch bar {
        case 0..<3: self = .weak
        case 3..<9: self = .normal
        case 9..<SMeter.overload - 1: self = .strong
        default: self = .overload
        }
    }
}

/// State and actions of the radio screen; the SwiftUI views only bind to it.
@MainActor
@Observable
public final class RadioViewModel {
    public enum Connection: Hashable, Sendable, Identifiable {
        case bluetooth
        /// One radio, chosen from a scan.
        case bluetoothDevice(BLEDevice)
        /// A USB serial device path.
        case serial(String)
        case simulator

        public var id: String { label }

        public var label: String {
            switch self {
            case .bluetooth: "Bluetooth (first radio found)"
            case .bluetoothDevice(let device): device.label
            case .serial(let path): "USB " + String(path.reversed().prefix { $0 != "/" }.reversed())
            case .simulator: "Simulator"
            }
        }
    }

    /// An update of the radio's firmware over USB (`FirmwareActivity`).
    public enum FirmwareUpdate: Equatable, Sendable {
        case idle
        /// Waiting for the bootloader.
        case connecting
        case flashing(percent: Int)
        /// Flashed and verified; the app reconnects.
        case finished
        /// The firmware for the Android app is flashed and verified; this app stays disconnected from it.
        case finishedForAndroid
        case failed(String)

        public var isRunning: Bool {
            switch self {
            case .connecting, .flashing: true
            case .idle, .finished, .finishedForAndroid, .failed: false
            }
        }
    }

    public private(set) var connections: [Connection] = []
    public private(set) var firmwareUpdate = FirmwareUpdate.idle
    public var selectedConnection = Connection.bluetooth {
        didSet {
            switch selectedConnection {
            case .bluetooth: bluetoothRadio = nil
            case .bluetoothDevice(let device): bluetoothRadio = device
            case .serial, .simulator: break
            }
            refreshConnections()
            saveSettings()
        }
    }
    public private(set) var snapshot = RadioViewModel.disconnected
    /// The frequency field, in MHz.
    public var frequencyText = ""
    /// The last problem, in words for the user.
    public private(set) var message: String? {
        didSet { isNoticeSuccess = false }
    }
    /// `notice` reports something that worked.
    public private(set) var isNoticeSuccess = false
    /// A failed connection, for the dialog; `nil` when no dialog is open (ADR-0039).
    public private(set) var alertMessage: String?

    private static let disconnected = RadioSnapshot(
        status: .disconnected,
        desired: DesiredStateController().desired,
        isInSync: false
    )
    /// Output gain of the RX audio, 0…1.
    public var volume: Float = 1 {
        didSet { rxAudio.volume = volume }
    }
    /// The signal the simulator receives (`canSimulateSignal`).
    public var simulatedSignal: SimulatedSignal? {
        didSet {
            guard simulatedSignal != oldValue, let simulator else { return }
            let signal = simulatedSignal
            Task { await simulator.setSignal(signal) }
        }
    }
    /// How the simulator behaves from the next connection.
    public var simulatorSettings = SimulatorSettings() {
        didSet {
            simulator?.settings = simulatorSettings
            saveSettings()
        }
    }

    public var micGain = MicGain.none {
        didSet { saveSettings() }
    }
    /// A PTT press starts transmitting, the next one ends it (Android "Sticky PTT").
    public var isStickyPTT = false {
        didSet { saveSettings() }
    }
    /// The tone that opens a repeater, in Hz; 0 for none.
    public var accessToneHz = 0 {
        didSet { saveSettings() }
    }
    public var accessToneLengthMs = AccessTone.defaultLengthMs {
        didSet { saveSettings() }
    }
    public var accessToneWaitMs = AccessTone.defaultWaitMs {
        didSet { saveSettings() }
    }
    /// What other apps do while the radio is busy.
    public var otherAudioMode = OtherAudioMode.pausePodcasts {
        didSet {
            otherAudio?.mode = otherAudioMode
            saveSettings()
        }
    }
    /// How long the squelch stays closed before other apps return.
    public var otherAudioResumeSeconds = 3 {
        didSet {
            otherAudio?.resumeAfter = .seconds(otherAudioResumeSeconds)
            saveSettings()
        }
    }
    public static let otherAudioResumeOptions = [1, 2, 3, 5, 10]
    /// What this platform can do with other apps.
    public let otherAudioModes: [OtherAudioMode]
    /// The frequencies the app may transmit on, per band.
    public var txLimits = TXLimits() {
        didSet {
            saveSettings()
            let limits = txLimits
            Task { await controller?.setTXLimits(limits) }
        }
    }

    /// All stored memories, in their stored order.
    public private(set) var memories: [ChannelMemory] = []
    /// The group shown; `nil` for all memories.
    public var selectedGroup: String? {
        didSet { saveSettings() }
    }

    /// The units of the APRS list.
    public var units = APRSUnits.system {
        didSet { saveSettings() }
    }

    /// The list stays across restarts (ADR-0057).
    public var isKeepingPackets = true {
        didSet { saveSettings() }
    }
    /// Packets only from the internet are stored as well.
    public var keepsInternetPackets = false {
        didSet { saveSettings() }
    }
    /// How long packets stay, in days; 0 for without limit.
    public var packetRetentionDays = 30 {
        didSet {
            saveSettings()
            if !isRestoring {
                pruneAPRSHistory()
            }
        }
    }
    public private(set) var storedPacketCount = 0

    /// The list on the main page, newest first.
    public var aprsEvents: [APRSEvent] { aprsEvents(in: .main) }
    public var hasMoreAPRSHistory: Bool { hasMoreAPRSHistory(in: .main) }

    public func aprsEvents(in list: APRSList) -> [APRSEvent] {
        self[list].events
    }

    /// Older packets are stored than the list shows.
    public func hasMoreAPRSHistory(in list: APRSList) -> Bool {
        self[list].hasMore
    }

    public func aprsFilter(in list: APRSList = .main) -> APRSListFilter {
        self[list].filter
    }

    let rxAudio = RXAudioPlayer()
    /// The station's callsign for APRS, normalised; empty disables sending. Kept apart from `aprs`, which is still
    /// being changed when its callbacks read the callsign.
    public var callsign = "" {
        didSet {
            aprs.callsign = callsign
            if callsign != aprs.callsign {
                callsign = aprs.callsign
            }
            updateInternet()
            saveSettings()
            endTransmissionIfBlocked()
            updateBeaconSession()
        }
    }
    /// The app does not transmit, by the user's choice; the iGate and the feed stay available (ADR-0047).
    public var isListenOnly = false {
        didSet {
            saveSettings()
            endTransmissionIfBlocked()
            updateBeaconSession()
        }
    }
    /// Asked once, at a start without a callsign or listen-only, not while the callsign is edited in the settings.
    public private(set) var isStationSetupPending = false
    /// The settings for all devices follow the user through iCloud (ADR-0051).
    public var isSettingsSyncEnabled = true {
        didSet {
            saveSettings()
            if !isRestoring {
                startSettingsSync()
            }
        }
    }
    /// When this device last exchanged settings with iCloud; the system decides when they travel on.
    public private(set) var lastSettingsSync: Date?
    /// When a sync of the memories with iCloud last finished.
    public private(set) var lastMemorySync: Date?
    /// Why the sync cannot work at the moment, though it is on.
    public private(set) var settingsSyncHint: String?
    /// iGate: pass received RF packets and our own packets to APRS-IS.
    public var isIGateEnabled = false {
        didSet {
            aprs.isIGateEnabled = isIGateEnabled
            updateInternet()
            saveSettings()
        }
    }
    /// Show APRS-IS packets near our position in the feed.
    public var isInternetFeedEnabled = false {
        didSet {
            internetLocation = nil
            updateInternet()
            saveSettings()
            if isInternetFeedEnabled, let location {
                Task { await locateInternetFilter(with: location) }
            }
        }
    }
    /// An APRS-IS connection is available.
    public var canUseInternet: Bool { internet != nil }
    /// APRS-IS logs in with the callsign, so it needs one.
    public var canUseInternetWithCallsign: Bool { canUseInternet && !callsign.isEmpty }
    /// Anything may go out on air: the one rule in front of every way to transmit (ADR-0047).
    public var canSendOnAir: Bool { !callsign.isEmpty && !isListenOnly }

    /// Neither of the two choices is made, so nothing goes out, which may not be what the user wants.
    public var stationWarning: String? {
        callsign.isEmpty && !isListenOnly
            ? "Without a callsign, nothing goes out. Enter one, or choose Listen only." : nil
    }

    /// Takes what the user entered; only an empty field keeps asking.
    public func completeStationSetup(callsign entered: String) {
        callsign = entered
        isStationSetupPending = callsign.isEmpty
    }

    public func chooseListenOnly() {
        isListenOnly = true
        isStationSetupPending = false
    }

    private func endTransmissionIfBlocked() {
        guard !canSendOnAir, isTransmitting, let controller else { return }
        isPTTHeld = false
        Task {
            await controller.stopTransmitting()
            show(await controller.snapshot)
        }
    }
    /// Logged in to APRS-IS.
    public private(set) var isInternetConnected = false

    /// Send a position beacon now and every five minutes (`AprsBeaconSchedule`).
    public var isBeaconEnabled = false {
        didSet {
            if isBeaconEnabled != oldValue {
                nextBeaconAtMs = 0
            }
            saveSettings()
            updateBeaconSession()
        }
    }
    /// How often the beacon goes out; a shorter time counts from now.
    public var beaconIntervalMinutes = 5 {
        didSet {
            nextBeaconAtMs = min(nextBeaconAtMs, now() + beaconIntervalMs)
            saveSettings()
        }
    }
    /// The beacon goes on with the screen locked, where the system would stop it otherwise.
    public var isBackgroundBeaconEnabled = true {
        didSet {
            saveSettings()
            updateBeaconSession()
        }
    }
    /// The app is on screen. Where a session is needed for the background, this decides when it can start.
    public var isAppActive = true {
        didSet { updateBeaconSession() }
    }
    /// The system limits the location in the background here, so the choice is offered.
    public var supportsBackgroundBeacon: Bool { backgroundLocation != nil }
    public var beaconSymbol = APRSSymbol.phone {
        didSet { saveSettings() }
    }
    public var beaconAccuracy = BeaconAccuracy.exact {
        didSet { saveSettings() }
    }
    /// MHz, one of `AppSettings.beaconFrequencyOptions`; `nil` beacons on the current TX frequency.
    public var beaconFrequency: Float? {
        didSet { saveSettings() }
    }
    /// Repeat packets for WIDE1-1 and our callsign.
    public var isDigipeatingEnabled: Bool {
        get { aprs.isDigipeatingEnabled }
        set {
            aprs.isDigipeatingEnabled = newValue
            saveSettings()
        }
    }
    /// `aprsBeaconTxOverrideMhz`: set while a beacon is submitted.
    private var beaconOverride: Float?
    /// The APRS list is on screen, so it can use our position (ADR-0053).
    public var isAPRSVisible = false {
        didSet { refreshOwnPosition() }
    }
    /// The same for the packets page of the settings.
    public var isPacketsPageVisible = false {
        didSet { refreshOwnPosition() }
    }
    /// Our position, for the distances of the APRS list; it stays on this device.
    public private(set) var ownPosition: GeoPoint?
    /// The question for location access is open, so the list can offer to ask it.
    public private(set) var offersDistances = false
    private var nextOwnPositionAtMs: Int64 = 0
    /// How often the list reads the position at most.
    private static let ownPositionIntervalMs: Int64 = 60_000

    /// A location is available for beacons.
    public var canBeacon: Bool { location != nil && !isDenied(.location) }

    static let beaconIntervalMs: Int64 = 5 * 60_000
    private var nextBeaconAtMs: Int64 = 0
    private var beaconIntervalMs: Int64 { Int64(beaconIntervalMinutes) * 60_000 }
    private let backgroundLocation: (any BackgroundLocationKeeping)?
    private var isBeaconSessionRunning = false
    /// A failed beacon was reported, and none has worked since.
    private var didReportBeaconFailure = false
    private let location: (any LocationProvider)?
    private let internet: (any APRSInternetLink)?
    private var internetLocation: GeoPoint?
    private var internetObservers: [Task<Void, Never>] = []
    private var aprs: APRSController
    private var packetObserver: Task<Void, Never>?
    private var aprsTicker: Task<Void, Never>?
    private let aprsTickInterval: Duration
    private let now: () -> Int64
    private let makeController: (Connection, any RXAudioSink) -> any RadioControlling
    private let serialDevices: () -> [String]
    private let bluetoothScanner: (any BLEScanning)?
    private let failureAlerts: (any FailureAlerting)?
    private let permissions: (any PermissionChecking)?
    private var deniedPermissions: Set<Permission> = []
    private var permissionObserver: Task<Void, Never>?
    private var bluetoothRadio: BLEDevice?
    private var foundRadios: [BLEDevice] = []
    private var isBluetoothScanWanted = false
    private var bluetoothScan: Task<Void, Never>?
    private let audioOutput: (any AudioOutput)?
    private let audioSession: (any AudioSession)?
    private var audioSessionObserver: Task<Void, Never>?
    private var otherAudio: OtherAudioController?
    /// The finger is on PTT, or a sticky PTT was pressed; lowering other apps takes a moment.
    private var isPTTHeld = false
    private let simulator: (any SimulatorControlling)?
    private let simulatedFlashStep: Duration
    private let simulatedSignalStep: Duration
    private var signalRamp: Task<Void, Never>?
    private let repository: (any MemoryRepository)?
    private let firmware: (any FirmwareFlashing)?
    /// What the flasher can write, the one for this app first (ADR-0049).
    public let firmwareChoices: [FirmwareChoice]
    private let aprsHistory: (any APRSHistoryStoring)?
    /// How many packets memory holds, and how many a step of the list brings.
    private let aprsListLimit: Int
    /// What each list shows: both use the packets in memory, and each brings back its own older ones.
    private var mainAPRSList = APRSListState()
    private var pageAPRSList = APRSListState()
    private subscript(list: APRSList) -> APRSListState {
        get { list == .main ? mainAPRSList : pageAPRSList }
        set {
            if list == .main {
                mainAPRSList = newValue
            } else {
                pageAPRSList = newValue
            }
        }
    }
    /// The stored state of the packets in memory, to save only what changed.
    private var storedAPRSEvents: [Int64: APRSEvent] = [:]
    /// Packets wait to be stored until the stored ones are back, as ids must not repeat.
    private var isAPRSHistoryLoaded = false
    private var nextAPRSPruneAtMs: Int64 = 0
    private var aprsHistoryWork: Task<Void, Never>?
    private static let aprsPruneIntervalMs: Int64 = 3_600_000
    private let settingsStore: (any SettingsStore)?
    private let syncedSettings: (any SyncedSettingsStore)?
    private let settingsSyncSleep: @Sendable (Duration) async throws -> Void
    private var settingsSync: SettingsSync?
    private var memoryObservers: [Task<Void, Never>] = []
    private var settingsSyncTask: Task<Void, Never>?
    /// How long changes must pause before they go to the other devices.
    static let settingsSyncPause = Duration.seconds(2)
    /// Restoring the settings, which must not save them again.
    private var isRestoring = false
    private var controller: (any RadioControlling)?
    private var connection: Connection?
    private var observer: Task<Void, Never>?
    /// The frequency shown when the field is reset.
    private var frequency: Float?

    /// `makeController` connects the RX audio of the radio to the given sink; `simulateSignal` starts or ends a
    /// carrier on the simulator.
    public init(
        makeController: @escaping (Connection, any RXAudioSink) -> any RadioControlling,
        serialDevices: @escaping () -> [String],
        audioOutput: (any AudioOutput)? = nil,
        audioSession: (any AudioSession)? = nil,
        otherAppsMute: (any OtherAudioSwitching)? = nil,
        memories: (any MemoryRepository)? = nil,
        location: (any LocationProvider)? = nil,
        backgroundLocation: (any BackgroundLocationKeeping)? = nil,
        internet: (any APRSInternetLink)? = nil,
        firmware: (any FirmwareFlashing)? = nil,
        firmwareChoices: [FirmwareChoice] = [],
        aprsHistory: (any APRSHistoryStoring)? = nil,
        settings: (any SettingsStore)? = nil,
        syncedSettings: (any SyncedSettingsStore)? = nil,
        bluetoothScanner: (any BLEScanning)? = nil,
        failureAlerts: (any FailureAlerting)? = nil,
        permissions: (any PermissionChecking)? = nil,
        simulator: (any SimulatorControlling)? = nil,
        simulatedFlashStep: Duration = .milliseconds(400),
        simulatedSignalStep: Duration = .seconds(1),
        otherAudioSleep: @escaping @Sendable (Duration) async throws -> Void = RadioViewModel.systemSleep,
        settingsSyncSleep: @escaping @Sendable (Duration) async throws -> Void = RadioViewModel.systemSleep,
        now: @escaping () -> Int64 = RadioViewModel.systemTimeMs,
        aprsTickInterval: Duration = .milliseconds(500),
        aprsListLimit: Int = 500
    ) {
        repository = memories
        self.firmware = firmware
        self.firmwareChoices = firmwareChoices
        self.aprsHistory = aprsHistory
        self.aprsListLimit = aprsListLimit
        settingsStore = settings
        self.syncedSettings = syncedSettings
        self.settingsSyncSleep = settingsSyncSleep
        self.bluetoothScanner = bluetoothScanner
        self.failureAlerts = failureAlerts
        self.permissions = permissions
        self.location = location
        self.backgroundLocation = backgroundLocation
        self.internet = internet
        self.now = now
        self.aprsTickInterval = aprsTickInterval
        var aprs = APRSController(startMs: now())
        aprs.txDestination = Self.aprsDestination
        aprs.txPath = ["WIDE1-1", "WIDE2-1"].compactMap(AX25Address.init)
        self.aprs = aprs
        self.makeController = makeController
        self.serialDevices = serialDevices
        self.audioOutput = audioOutput
        self.audioSession = audioSession
        otherAudioModes =
            audioSession == nil && otherAppsMute != nil
            ? OtherAudioMode.withoutAudioSession : OtherAudioMode.withAudioSession
        self.simulator = simulator
        self.simulatedFlashStep = simulatedFlashStep
        self.simulatedSignalStep = simulatedSignalStep
        refreshConnections()
        observeInternet()
        observeMemories()
        observeAudioSession()
        observePermissions()
        if let switching = audioSession ?? otherAppsMute {
            otherAudio = OtherAudioController(
                session: switching,
                output: audioSession == nil ? nil : audioOutput,
                player: rxAudio,
                prepareMicrophone: { [weak self] in await self?.controller?.prepareMicrophone() },
                reportFailure: { [weak self] in self?.message = $0 },
                sleep: otherAudioSleep,
                releaseWait: audioSession == nil ? .zero : OtherAudioController.podcastReturnWait
            )
        }
        restore(AppSettings(data: settings?.load()))
        syncedSettings?.observeChanges { [weak self] in
            Task { @MainActor [weak self] in self?.receiveSettings(fromCloud: true) }
        }
        startSettingsSync()
        refreshPermissions()
        loadAPRSHistory()
    }

    // MARK: Settings

    /// The app settings as they are now.
    public var settings: AppSettings {
        var settings = AppSettings()
        settings.callsign = callsign
        settings.isListenOnly = isListenOnly
        settings.isSettingsSyncEnabled = isSettingsSyncEnabled
        settings.lastSettingsSync = lastSettingsSync
        settings.lastMemorySync = lastMemorySync
        settings.micGain = micGain
        settings.isStickyPTT = isStickyPTT
        settings.accessToneHz = accessToneHz
        settings.accessToneLengthMs = accessToneLengthMs
        settings.accessToneWaitMs = accessToneWaitMs
        settings.otherAudioMode = otherAudioMode
        settings.otherAudioResumeSeconds = otherAudioResumeSeconds
        settings.isBeaconEnabled = isBeaconEnabled
        settings.beaconSymbol = beaconSymbol
        settings.beaconAccuracy = beaconAccuracy
        settings.beaconFrequency = beaconFrequency
        settings.beaconIntervalMinutes = beaconIntervalMinutes
        settings.isBackgroundBeaconEnabled = isBackgroundBeaconEnabled
        settings.isDigipeatingEnabled = isDigipeatingEnabled
        settings.isIGateEnabled = isIGateEnabled
        settings.isInternetFeedEnabled = isInternetFeedEnabled
        settings.aprsListFilter = aprsFilter(in: .main)
        settings.aprsPageFilter = aprsFilter(in: .packetsPage)
        settings.txLimits = txLimits
        settings.units = units
        settings.isKeepingPackets = isKeepingPackets
        settings.keepsInternetPackets = keepsInternetPackets
        settings.packetRetentionDays = packetRetentionDays
        settings.selectedGroup = selectedGroup
        settings.bluetoothRadio = bluetoothRadio
        settings.isSimulatorChosen = selectedConnection == .simulator
        settings.simulator = simulatorSettings
        return settings
    }

    /// `MainActivity.applySettings`.
    private func restore(_ settings: AppSettings) {
        isRestoring = true
        defer { isRestoring = false }
        applySynced(settings)
        isSettingsSyncEnabled = settings.isSettingsSyncEnabled
        lastSettingsSync = settings.lastSettingsSync
        isBackgroundBeaconEnabled = settings.isBackgroundBeaconEnabled
        lastMemorySync = settings.lastMemorySync
        isListenOnly = settings.isListenOnly
        isStationSetupPending = callsign.isEmpty && !isListenOnly
        micGain = settings.micGain
        otherAudioMode = otherAudioModes.contains(settings.otherAudioMode) ? settings.otherAudioMode : .keepPlaying
        otherAudioResumeSeconds = settings.otherAudioResumeSeconds
        isBeaconEnabled = settings.isBeaconEnabled
        isDigipeatingEnabled = settings.isDigipeatingEnabled
        isIGateEnabled = settings.isIGateEnabled
        isInternetFeedEnabled = settings.isInternetFeedEnabled
        selectedGroup = settings.selectedGroup
        simulatorSettings = settings.simulator
        if let radio = settings.bluetoothRadio {
            selectedConnection = .bluetoothDevice(radio)
        }
        if settings.isSimulatorChosen {
            selectedConnection = .simulator
        }
    }

    /// The settings for all devices, as `SettingsSync` lists them.
    private func applySynced(_ settings: AppSettings) {
        callsign = settings.callsign
        isStickyPTT = settings.isStickyPTT
        accessToneHz = settings.accessToneHz
        accessToneLengthMs = settings.accessToneLengthMs
        accessToneWaitMs = settings.accessToneWaitMs
        beaconSymbol = settings.beaconSymbol
        beaconAccuracy = settings.beaconAccuracy
        beaconFrequency = settings.beaconFrequency
        beaconIntervalMinutes = settings.beaconIntervalMinutes
        self[.main].filter = settings.aprsListFilter
        self[.packetsPage].filter = settings.aprsPageFilter
        txLimits = settings.txLimits
        units = settings.units
        isKeepingPackets = settings.isKeepingPackets
        keepsInternetPackets = settings.keepsInternetPackets
        packetRetentionDays = settings.packetRetentionDays
    }

    private func saveSettings() {
        guard !isRestoring, let settingsStore, let data = try? settings.encoded() else { return }
        settingsStore.save(data)
        scheduleSettingsSync()
    }

    // MARK: Settings sync

    /// Sends what changed, once the changes have paused, so that typing a callsign is not sent letter by letter.
    private func scheduleSettingsSync() {
        guard settingsSync != nil else { return }
        settingsSyncTask?.cancel()
        settingsSyncTask = Task { [weak self, settingsSyncSleep] in
            guard (try? await settingsSyncSleep(Self.settingsSyncPause)) != nil else { return }
            self?.sendSettings()
        }
    }

    /// Before the app may be stopped, nothing should wait.
    public func flushSettingsSync() {
        settingsSyncTask?.cancel()
        sendSettings()
    }

    private func sendSettings() {
        let changed = settingsSync?.outgoing(settings) ?? [:]
        if !changed.isEmpty {
            syncedSettings?.set(changed)
            noteSettingsSynced()
        }
    }

    private func noteSettingsSynced() {
        guard syncedSettings?.isAvailable == true else { return }
        lastSettingsSync = Date(timeIntervalSince1970: Double(now()) / 1000)
        saveSettings()
    }

    private func startSettingsSync() {
        settingsSyncTask?.cancel()
        settingsSync = nil
        settingsSyncHint = nil
        guard isSettingsSyncEnabled, let syncedSettings else { return }
        settingsSync = SettingsSync(settings)
        receiveSettings()
        let unknown = SettingsSync.unknownToCloud(settings, remote: syncedSettings.values())
        if !unknown.isEmpty {
            syncedSettings.set(unknown)
            noteSettingsSynced()
        }
    }

    private func receiveSettings(fromCloud: Bool = false) {
        guard settingsSync != nil, let syncedSettings else { return }
        settingsSyncHint =
            syncedSettings.isAvailable ? nil : "iCloud is not available, so these settings stay on this device."
        guard let merged = settingsSync?.incoming(syncedSettings.values(), into: settings), merged != settings else {
            if fromCloud {
                noteSettingsSynced()
            }
            return
        }
        isRestoring = true
        applySynced(merged)
        isRestoring = false
        // The question at the start closes with a callsign; it does not open while the app is in use.
        isStationSetupPending = isStationSetupPending && callsign.isEmpty
        saveSettings()
        noteSettingsSynced()
    }

    /// Bluetooth with the radios found or remembered, the USB serial devices present, and the built-in simulator.
    public func refreshConnections() {
        var radios = foundRadios
        if let bluetoothRadio, !radios.contains(where: { $0.id == bluetoothRadio.id }) {
            radios.append(bluetoothRadio)
        }
        connections =
            [.bluetooth] + radios.sorted { $0.label < $1.label }.map(Connection.bluetoothDevice)
            + serialDevices().map(Connection.serial) + [.simulator]
    }

    /// Lists the radios in range, while no connection is up or being set up (ADR-0038).
    public func startBluetoothScan() {
        isBluetoothScanWanted = true
        updateBluetoothScan()
    }

    public func stopBluetoothScan() {
        isBluetoothScanWanted = false
        updateBluetoothScan()
    }

    private func updateBluetoothScan() {
        // Without a decision, a scan would ask for Bluetooth, which waits until the user connects.
        let isAllowed = permissions.map { $0.state(of: .bluetooth) == .granted } ?? true
        guard isBluetoothScanWanted, controller == nil || hasFailed, isAllowed else {
            bluetoothScan?.cancel()
            bluetoothScan = nil
            return
        }
        guard bluetoothScan == nil, let bluetoothScanner else { return }
        let radios = bluetoothScanner.scan()
        bluetoothScan = Task { [weak self] in
            for await found in radios {
                self?.show(found)
            }
        }
    }

    private func show(_ found: [BLEDevice]) {
        foundRadios = found
        if let renamed = found.first(where: { $0.id == bluetoothRadio?.id }), renamed != bluetoothRadio {
            if selectedConnection == bluetoothRadio.map(Connection.bluetoothDevice) {
                selectedConnection = .bluetoothDevice(renamed)
                return
            }
            bluetoothRadio = renamed
            saveSettings()
        }
        refreshConnections()
    }

    public var isReady: Bool { snapshot.status == .ready }

    /// The connection has failed; `statusText` says why.
    public var hasFailed: Bool {
        if case .failed = snapshot.status { return true }
        return false
    }

    /// A message to show besides the status, as a failed connection is the status itself.
    public var notice: String? { hasFailed ? nil : message }

    public func isDenied(_ permission: Permission) -> Bool {
        deniedPermissions.contains(permission)
    }

    /// The chosen connection needs the Bluetooth access the user has refused.
    public var isBluetoothBlocked: Bool {
        guard isDenied(.bluetooth) else { return false }
        switch selectedConnection {
        case .bluetooth, .bluetoothDevice: return true
        case .serial, .simulator: return false
        }
    }

    public var canStartConnection: Bool { canConnect && !isBluetoothBlocked && !firmwareUpdate.isRunning }

    /// Reads the permissions again; the beacon ends without location access and stays off afterwards.
    public func refreshPermissions() {
        deniedPermissions = Set(Permission.allCases.filter { permissions?.state(of: $0) == .denied })
        if isDenied(.location) {
            if isBeaconEnabled {
                report(Permission.location.deniedMessage)
            }
            isBeaconEnabled = false
            ownPosition = nil
        }
        updateBeaconSession()
        offersDistances = location != nil && permissions?.state(of: .location) == .notDetermined
        refreshOwnPosition()
        updateBluetoothScan()
    }

    private func observePermissions() {
        guard let changes = permissions?.changes else { return }
        permissionObserver = Task { [weak self] in
            for await _ in changes {
                self?.refreshPermissions()
            }
        }
    }

    /// Everything but Bluetooth, which the connection itself asks for; the simulator needs nothing real.
    private func askForPermissions() {
        guard selectedConnection != .simulator else { return }
        permissions?.request(.microphone)
        permissions?.request(.location)
        failureAlerts?.prepare()
    }

    public func askForDistances() {
        permissions?.request(.location)
    }

    /// Where the station of a packet is, and how far from here. A packet of our own has no distance.
    public func position(of event: APRSEvent) -> StationPosition? {
        StationPosition(event: event, own: event.fromCallsign == callsign ? nil : ownPosition)
    }

    /// Reads our position for the list: while it is shown, with access granted, and at most once a minute.
    private func refreshOwnPosition() {
        guard isAPRSVisible || isPacketsPageVisible, let location, permissions?.state(of: .location) == .granted,
            now() >= nextOwnPositionAtMs
        else { return }
        nextOwnPositionAtMs = now() + Self.ownPositionIntervalMs
        Task {
            if let point = await location.currentLocation() {
                ownPosition = point
            }
        }
    }

    public func dismissNotice() {
        message = nil
    }

    public var canConnect: Bool {
        switch snapshot.status {
        case .disconnected, .failed: true
        default: false
        }
    }

    /// A running or ended firmware update comes first, as there is no connection meanwhile.
    public var statusText: String { Self.statusLine(for: firmwareUpdate) ?? Self.statusText(for: snapshot) }

    /// Whether `statusText` reports a failure.
    public var isStatusFailure: Bool {
        switch firmwareUpdate {
        case .failed: true
        case .connecting, .flashing, .finishedForAndroid: false
        case .idle, .finished: hasFailed
        }
    }

    static func statusLine(for update: FirmwareUpdate) -> String? {
        switch update {
        case .idle, .finished: nil
        case .connecting: "Starting the bootloader…"
        case .flashing(let percent): "Updating firmware… \(percent) %"
        case .finishedForAndroid: "Firmware updated and verified. The radio is now set up for the Android app."
        case .failed(let message): message
        }
    }

    /// E.g. `Firmware 17 · VHF 134–174 MHz`.
    public var firmwareText: String? {
        snapshot.firmware.map { firmware in
            "Firmware \(firmware.version) · \(Self.band(of: firmware)) "
                + "\(Int(firmware.minRadioFreq))–\(Int(firmware.maxRadioFreq)) MHz"
        }
    }

    /// `VHF` or `UHF`, once the radio has reported its module.
    public var bandText: String? { snapshot.firmware.map(Self.band) }

    private static func band(of firmware: FirmwareVersion) -> String {
        firmware.moduleType == .sa818UHF ? "UHF" : "VHF"
    }

    /// The bars of the S-meter, the last one for overload.
    public nonisolated static let sMeterBarCount = SMeter.overload

    public var sMeter: Int { snapshot.sMeter }

    public var sMeterText: String { Self.sMeterText(for: sMeter) }

    /// The squelch is open: a signal is received and played.
    public var isReceiving: Bool {
        guard isReady, let flags = snapshot.deviceState?.radio.flags else { return false }
        return !flags.contains(.squelched)
    }

    /// PTT is pressed (the radio may not have keyed up yet).
    public var isTransmitting: Bool { snapshot.isTransmitting }

    /// The radio reports that it transmits.
    public var isOnAir: Bool { isReady && snapshot.deviceState?.radio.flags.contains(.txActive) == true }

    /// The TX frequency is inside the ham band.
    public var canTransmit: Bool { isReady && snapshot.desired.flags.contains(.txAllowed) }

    /// Why PTT cannot transmit on this frequency, with the range for the bandwidth.
    public var transmitBlockedText: String? {
        if isListenOnly { return Self.listenOnlyText }
        if callsign.isEmpty { return "Set your callsign to transmit." }
        guard isReady, !canTransmit, let firmware = snapshot.firmware else { return nil }
        let bandwidth = snapshot.desired.bandwidth
        let allowed = txLimits.band(for: firmware.moduleType).allowedRange(bandwidth: bandwidth)
        let lower = HamFrequency.formatLimit(allowed.lowerBound)
        let upper = HamFrequency.formatLimit(allowed.upperBound)
        return
            "Can't transmit here: with \(bandwidth == 1 ? "25" : "12.5") kHz, the allowed range is \(lower)–\(upper) MHz."
    }

    public var canSimulateSignal: Bool { isReady && connection == .simulator && simulator != nil }

    /// The simulator is the chosen radio, so its settings apply.
    public var canConfigureSimulator: Bool { selectedConnection == .simulator && simulator != nil }

    public var isSignalRampRunning: Bool { signalRamp != nil }

    /// Starts the signal through all strengths, up and down, then off; or ends it early.
    public func toggleSignalRamp() {
        guard signalRamp == nil else { return stopSignalRamp() }
        let step = simulatedSignalStep
        signalRamp = Task { [weak self] in
            for signal in SimulatedSignal.ramp {
                self?.simulatedSignal = signal
                try? await Task.sleep(for: step)
                guard !Task.isCancelled else { return }
            }
            self?.stopSignalRamp()
        }
    }

    private func stopSignalRamp() {
        signalRamp?.cancel()
        signalRamp = nil
        simulatedSignal = nil
    }

    public func loseSimulatedConnection() {
        guard let simulator else { return }
        Task { await simulator.loseConnection() }
    }

    public func simulatePacket(_ packet: SimulatedPacket) {
        guard let simulator, let frame = try? APRSParser.parse(tnc2: packet.tnc2(to: callsign)).ax25Frame() else {
            return
        }
        Task { await simulator.hear(frame) }
    }

    // MARK: Firmware

    /// Flashing needs USB and the bundled firmware, so only the Mac can.
    public var canUpdateFirmware: Bool {
        flashTarget != nil && !firmwareChoices.isEmpty && !firmwareUpdate.isRunning && !isTransmitting
    }

    /// What flashes the chosen radio: the flasher over USB, or on the Mac a stand-in for the simulator. Without a
    /// flasher (iOS), the simulator offers no update either, as with a real radio.
    private var flashTarget: (flasher: any FirmwareFlashing, path: String)? {
        guard let firmware else { return nil }
        switch selectedConnection {
        case .serial(let path): return (firmware, path)
        case .simulator: return simulator.map { _ in (SimulatedFirmwareFlasher(step: simulatedFlashStep), "") }
        case .bluetooth, .bluetoothDevice: return nil
        }
    }

    /// `outdatedFirmware` / `missingFirmware`: the radio's firmware is older than required, or it did not answer.
    public var isFirmwareOutdated: Bool {
        switch snapshot.status {
        case .failed(.firmwareTooOld), .failed(.firmwareForAndroid), .failed(.invalidHello), .failed(.helloTimeout):
            true
        default: false
        }
    }

    /// The radio's firmware keeps it from working with this app, which includes firmware without Bluetooth LE.
    private var hasFirmwareProblem: Bool {
        isFirmwareOutdated || snapshot.status == .failed(.transport(.serviceNotFound))
    }

    /// Firmware that this app cannot update itself (iOS): a Mac or the Android nightly app can.
    public var needsFirmwareUpdateElsewhere: Bool { firmware == nil && hasFirmwareProblem }

    /// Firmware that the settings can update (the Mac), so the app offers the way there.
    public var offersFirmwareSettings: Bool { firmware != nil && hasFirmwareProblem && !firmwareUpdate.isRunning }

    /// Why the update cannot start yet: it needs the radio on USB.
    public var firmwareUpdateHint: String? {
        offersFirmwareSettings && flashTarget == nil
            ? "Connect the radio by USB and choose it under Radio." : nil
    }

    /// The settings should open on the page with the firmware update.
    public private(set) var isFirmwareSettingsRequested = false

    public func requestFirmwareSettings() {
        isFirmwareSettingsRequested = true
    }

    public func firmwareSettingsShown() {
        isFirmwareSettingsRequested = false
    }

    /// `startFirmwareActivity`: disconnects and flashes `choice` into the radio on the selected USB device. Once it is
    /// verified, the app reconnects to the firmware for this app (`renegotiateAfterFlashing`), not to the other.
    public func updateFirmware(to choice: FirmwareChoice) async {
        guard canUpdateFirmware, let target = flashTarget else { return }
        await disconnect()
        firmwareUpdate = .connecting
        let (events, reporter) = AsyncStream.makeStream(of: FlashEvent.self)
        let progress = Task { [weak self] in
            for await event in events {
                guard case .progress(let percent) = event else { continue }
                self?.firmwareUpdate = .flashing(percent: percent)
            }
        }
        do throws(FlashError) {
            try await target.flasher.flash(choice.images, serialPath: target.path) { reporter.yield($0) }
            reporter.finish()
            await progress.value
            let isForThisApp = choice.edition == .forThisApp
            firmwareUpdate = isForThisApp ? .finished : .finishedForAndroid
            if canConfigureSimulator { simulatorSettings.firmware = isForThisApp ? .current : .android }
            if isForThisApp { await connect() }
        } catch {
            reporter.finish()
            await progress.value
            firmwareUpdate = .failed(Self.message(for: error))
        }
    }

    // MARK: Connection

    public func connect() async {
        switch firmwareUpdate {
        case .failed, .finishedForAndroid: firmwareUpdate = .idle
        case .idle, .connecting, .flashing, .finished: break
        }
        bluetoothScan?.cancel()
        bluetoothScan = nil
        await tearDown()
        askForPermissions()
        let controller = makeController(selectedConnection, rxAudio)
        self.controller = controller
        await controller.setTXLimits(txLimits)
        connection = selectedConnection
        message = nil
        frequency = nil
        startAudio()
        let snapshots = controller.snapshots
        observer = Task { [weak self] in
            for await snapshot in snapshots where !Task.isCancelled {
                self?.show(snapshot)
            }
        }
        let frames = controller.receivedFrames
        packetObserver = Task { [weak self] in
            for await frame in frames {
                self?.receive(frame)
            }
        }
        let interval = aprsTickInterval
        aprsTicker = Task { [weak self] in
            while (try? await Task.sleep(for: interval)) != nil {
                self?.tickAPRS()
            }
        }
        await controller.connect()
    }

    public func disconnect() async {
        await tearDown()
        refreshPermissions()
    }

    private func tearDown() async {
        observer?.cancel()
        observer = nil
        packetObserver?.cancel()
        packetObserver = nil
        aprsTicker?.cancel()
        aprsTicker = nil
        await otherAudio?.stop()
        await controller?.disconnect()
        audioOutput?.stop()
        audioSession?.deactivate()
        controller = nil
        connection = nil
        stopSignalRamp()
        snapshot = Self.disconnected
        updateBeaconSession()
    }

    private func show(_ snapshot: RadioSnapshot) {
        guard snapshot.revision >= self.snapshot.revision else { return }  // already showing a newer one
        let hadFailed = hasFailed
        self.snapshot = snapshot
        updateBeaconSession()
        if case .failed(let failure) = snapshot.status {
            let text = Self.message(for: failure)
            message = text
            if !hadFailed { report(text) }
            refreshPermissions()
        }
        if snapshot.status == .ready, let reported = snapshot.deviceState?.radio.freqRx, reported != frequency {
            frequency = reported
            frequencyText = HamFrequency.format(reported)
        }
        // The access tone keeps the microphone closed, so nothing of other apps goes on air.
        let isUsingMicrophone = isTransmitting && !snapshot.isSendingAccessTone
        otherAudio?.update(isBusy: isUsingMicrophone || (isReceiving && squelch > 0))
    }

    private func report(_ text: String) {
        if failureAlerts?.usesDialog == true {
            alertMessage = text
        }
        failureAlerts?.deliver(text)
    }

    public func dismissAlert() {
        alertMessage = nil
    }

    // MARK: Audio session

    private func startAudio() {
        do {
            try audioSession?.activate()
            try audioOutput?.start(rxAudio)
        } catch {
            message = "The audio output cannot be started."
        }
    }

    public nonisolated static let systemSleep: @Sendable (Duration) async throws -> Void = {
        try await Task.sleep(for: $0)
    }

    /// iOS has a session for other apps, the Mac a tap on them; a platform without either offers nothing.
    public var canChooseOtherAudio: Bool { otherAudio != nil }

    /// Squelch 0 is always open, so the radio could never hand the sound back.
    public var otherAudioHint: String? {
        guard isReady, squelch == 0, otherAudioMode.changesOtherAudio else { return nil }
        return "While the squelch is 0, only transmitting does this."
    }

    private func observeAudioSession() {
        guard let events = audioSession?.events else { return }
        audioSessionObserver = Task { [weak self] in
            for await event in events {
                await self?.handle(event)
            }
        }
    }

    /// A call or another app ends the transmission and the audio until the system allows it again; a lost device
    /// ends the transmission, so it does not go on with another microphone.
    func handle(_ event: AudioSessionEvent) async {
        guard let controller else { return }
        switch event {
        case .interruptionBegan:
            await otherAudio?.interrupted()
            await controller.stopTransmitting()
            audioOutput?.stop()
        case .interruptionEnded(let shouldResume):
            if shouldResume {
                startAudio()
            } else {
                message = "The audio was interrupted. Connect again to listen."
            }
            otherAudio?.interruptionEnded(canResume: shouldResume)
        case .deviceUnavailable:
            await controller.stopTransmitting()
        case .mediaServicesReset:
            await otherAudio?.stop()
            await controller.stopTransmitting()
            audioOutput?.stop()
            startAudio()
        }
        show(await controller.snapshot)
    }

    // MARK: APRS

    /// Milliseconds since 1970, the time base of APRS events.
    public nonisolated static let systemTimeMs: @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }

    /// Frames that are not APRS are ignored, as on Android.
    private func receive(_ frame: [UInt8]) {
        guard let packet = try? APRSParser.parse(ax25: frame) else { return }
        aprs.receive(
            packet,
            frame: frame,
            frequencyHz: rxFrequencyHz,
            atMs: now(),
            transmit: transmitAPRS,
            gate: gateAPRS
        )
        showAPRS()
    }

    /// The AX.25 destination of the Android app (`APRS_TOCALL`).
    static let aprsDestination = "APKVPA"

    /// The frequency packets are received on, in Hz.
    private var rxFrequencyHz: Int64? {
        snapshot.deviceState.map { Self.hertz($0.radio.freqRx) }
    }

    /// `AprsRfFrequencyPolicy.toHz`: via the decimal text of the `Float`, so 144.8 is 144 800 000 Hz.
    static func hertz(_ megahertz: Float) -> Int64 {
        Int64((strtod(megahertz.description, nil) * 1_000_000).rounded())
    }

    private static let listenOnlyText = "Listen only: this app does not transmit."

    /// `sendChatMessage`: `|`, `~` and `{` become spaces; without a recipient the message is the bulletin BLN1CQ.
    public func sendAPRSMessage(to recipient: String, text: String) {
        guard !callsign.isEmpty else {
            message = "Set your callsign to send APRS messages."
            return
        }
        guard canSendOnAir else {
            message = Self.listenOnlyText
            return
        }
        let cleaned = String(text.map { "|~{".contains($0) ? " " : $0 })
        let to = recipient.trimmingCharacters(in: .whitespaces).isEmpty ? "BLN1CQ" : recipient
        let frequency = Self.hertz(snapshot.desired.freqTx)
        let posted = aprs.post(
            to: to,
            text: cleaned,
            frequencyHz: frequency,
            atMs: now(),
            transmit: transmitAPRS,
            gate: gateAPRS
        )
        if !posted {
            message = "The APRS message was not accepted for transmission."
        }
        showAPRS()
    }

    private func tickAPRS() {
        isInternetConnected = internet?.isLoggedIn ?? false
        let time = now()
        aprs.tick(atMs: time, transmit: transmitAPRS)
        updateBeaconSession()
        if isBeaconEnabled, canSendOnAir, canReadLocationNow, time >= nextBeaconAtMs, let location {
            nextBeaconAtMs = time + beaconIntervalMs
            Task { await beacon(from: location) }
        }
        showAPRS()
    }

    /// In the background, only a session keeps the location available where the system limits it.
    private var canReadLocationNow: Bool {
        isAppActive || backgroundLocation == nil || isBeaconSessionRunning
    }

    /// Starts or ends the session as the beacon needs it (ADR-0056). It can only start in the foreground.
    private func updateBeaconSession() {
        let isWanted =
            isBackgroundBeaconEnabled && isBeaconEnabled && canSendOnAir && isReady && !isDenied(.location)
        if isWanted, !isBeaconSessionRunning, isAppActive, let backgroundLocation {
            backgroundLocation.start()
            isBeaconSessionRunning = true
        } else if !isWanted, isBeaconSessionRunning {
            backgroundLocation?.stop()
            isBeaconSessionRunning = false
        }
    }

    /// `sendPositionBeacon`: compressed, messaging capable, primary table, on the current TX frequency.
    private func beacon(from location: any LocationProvider) async {
        guard let point = await location.currentLocation() else {
            message = "Your location is unknown."
            if !didReportBeaconFailure {
                didReportBeaconFailure = true
                report("Your location is unknown.")
            }
            return
        }
        didReportBeaconFailure = false
        ownPosition = point
        let beacon = APRSBeacon(
            latitude: beaconAccuracy.rounded(point.latitude),
            longitude: beaconAccuracy.rounded(point.longitude),
            symbolTable: "/",
            symbolCode: beaconSymbol.code
        )
        beaconOverride = beaconFrequency
        _ = aprs.submitBeacon(beacon, atMs: now(), transmit: transmitAPRS, gate: gateAPRS)
        beaconOverride = nil
        showAPRS()
    }

    private func showAPRS() {
        storeAPRSEvents()
        for list in APRSList.allCases {
            var state = self[list]
            state.events = (aprs.events + state.older)
                .filter { state.filter.matches($0, ownCallsign: callsign) }
                .sorted { $0.lastSeenMs > $1.lastSeenMs }
            self[list] = state
        }
        if aprs.events.contains(where: { position(of: $0) != nil }) {
            refreshOwnPosition()
        }
    }

    // MARK: APRS history

    /// One step after the other, so that a later change of a packet is not overwritten by an earlier one.
    private func withAPRSHistory(_ work: @escaping @MainActor (any APRSHistoryStoring) async throws -> Void) {
        guard let aprsHistory else { return }
        let previous = aprsHistoryWork
        aprsHistoryWork = Task { [weak self] in
            await previous?.value
            do {
                try await work(aprsHistory)
                self?.storedPacketCount = try await aprsHistory.count()
            } catch {
                self?.message = "The APRS history could not be read or saved."
            }
        }
    }

    private func loadAPRSHistory() {
        withAPRSHistory { [weak self] history in
            guard let self else { return }
            defer { self.isAPRSHistoryLoaded = true }
            guard self.isKeepingPackets else { return }
            self.pruneAPRSHistory()
            let page = try await history.page(before: nil, limit: self.aprsListLimit)
            let highestId = try await history.highestId()
            let stored = page.reversed().compactMap(Self.event)
            self.storedAPRSEvents = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0) })
            self.aprs.restore(stored, highestId: highestId)
            self.isAPRSHistoryLoaded = true
            for list in APRSList.allCases {
                if self.aprsFilter(in: list).isEmpty {
                    self.self[list].hasMore = page.count == self.aprsListLimit
                } else {
                    try await self.loadPage(of: list, from: history)
                }
            }
            self.showAPRS()
        }
    }

    private static func event(_ entry: APRSHistoryEntry) -> APRSEvent? {
        try? JSONDecoder().decode(APRSEvent.self, from: entry.payload)
    }

    /// Stores what is new or changed, and keeps memory from growing with the history.
    private func storeAPRSEvents() {
        guard isAPRSHistoryLoaded else { return }
        if isKeepingPackets {
            if now() >= nextAPRSPruneAtMs {
                pruneAPRSHistory()
            }
            let changed = aprs.events.filter { shouldStore($0) && storedAPRSEvents[$0.id] != $0 }
            if !changed.isEmpty {
                for event in changed {
                    storedAPRSEvents[event.id] = event
                }
                let entries = changed.compactMap(Self.entry)
                withAPRSHistory { try await $0.save(entries) }
            }
        }
        for event in aprs.trim(keeping: aprsListLimit) {
            storedAPRSEvents[event.id] = nil
            if isKeepingPackets, shouldStore(event) {
                for list in APRSList.allCases where aprsFilter(in: list).isEmpty {
                    self[list].hasMore = true
                }
            }
        }
    }

    /// Messages to or from this station stay, wherever they came from.
    private func shouldStore(_ event: APRSEvent) -> Bool {
        !event.isInternetOnly || keepsInternetPackets || event.isMessage(of: callsign)
    }

    private static func entry(_ event: APRSEvent) -> APRSHistoryEntry? {
        (try? JSONEncoder().encode(event)).map { payload in
            APRSHistoryEntry(
                id: event.id,
                lastSeenMs: event.lastSeenMs,
                kind: event.kind.rawValue,
                fromCallsign: event.fromCallsign,
                toCallsign: event.toCallsign,
                isInternetOnly: event.isInternetOnly,
                payload: payload
            )
        }
    }

    private func pruneAPRSHistory() {
        nextAPRSPruneAtMs = now() + Self.aprsPruneIntervalMs
        guard packetRetentionDays > 0 else { return }
        let oldest = now() - Int64(packetRetentionDays) * 86_400_000
        aprs.removeEvents { $0.lastSeenMs < oldest && $0.deliveryState != .pending }
        for list in APRSList.allCases {
            self[list].older.removeAll { $0.lastSeenMs < oldest }
        }
        storedAPRSEvents = storedAPRSEvents.filter { $0.value.lastSeenMs >= oldest }
        withAPRSHistory { try await $0.deleteOlder(than: oldest) }
        if isAPRSHistoryLoaded {
            showAPRS()
        }
    }

    /// Brings the next older packets to a list.
    public func loadMoreAPRSHistory(in list: APRSList = .main) async {
        withAPRSHistory { [weak self] history in
            try await self?.loadPage(of: list, from: history)
            self?.showAPRS()
        }
        await aprsHistoryWork?.value
    }

    private func loadPage(of list: APRSList, from history: any APRSHistoryStoring) async throws {
        var state = self[list]
        let shown = aprs.events + state.older
        // Without a filter, memory holds the newest; with one, a packet that fits can be anywhere.
        let start = state.cursor ?? (state.filter.isEmpty ? shown.map(\.lastSeenMs).min() : nil)
        // The last one comes again, so that packets of the same moment are not missed.
        let page = try await history.page(
            before: start,
            limit: aprsListLimit + 1,
            filter: historyFilter(state.filter)
        )
        let known = Set(shown.map(\.id))
        state.older += page.compactMap(Self.event).filter { !known.contains($0.id) }
        state.cursor = page.last?.lastSeenMs ?? start
        state.hasMore = page.count > aprsListLimit
        self[list] = state
    }

    /// Looks for packets over all that is stored. The filter is remembered on this device.
    public func setAPRSFilter(_ filter: APRSListFilter, in list: APRSList = .main) async {
        self[list] = APRSListState(filter: filter)
        saveSettings()
        showAPRS()
        guard aprsHistory != nil else { return }
        if filter.isEmpty {
            await aprsHistoryWork?.value
            self[list].hasMore = storedPacketCount > aprs.events.count
        } else {
            await loadMoreAPRSHistory(in: list)
        }
    }

    /// What the store looks for: as near as it can, as `APRSListFilter` decides in the end.
    private func historyFilter(_ filter: APRSListFilter) -> APRSHistoryFilter {
        APRSHistoryFilter(
            callsign: filter.callsign,
            kinds: Set(filter.kinds.map(\.rawValue)),
            participant: filter.isForMe ? APRSEvent.baseCallsign(callsign) : ""
        )
    }

    /// A list as its filter shows it, oldest first: all that is stored, and what is only in memory. `nil` if the store
    /// cannot be read.
    public func exportAPRS(_ format: APRSExport.Format, from list: APRSList = .main) async -> String? {
        let filter = aprsFilter(in: list)
        var older: [APRSEvent] = []
        var wasRead = aprsHistory == nil
        withAPRSHistory { [weak self] history in
            guard let self else { return }
            var start: Int64?
            var seen = Set<Int64>()
            while true {
                let page = try await history.page(
                    before: start,
                    limit: self.aprsListLimit + 1,
                    filter: self.historyFilter(filter)
                )
                older += page.compactMap(Self.event).filter { seen.insert($0.id).inserted }
                start = page.last?.lastSeenMs
                if page.count <= self.aprsListLimit { break }
            }
            wasRead = true
        }
        await aprsHistoryWork?.value
        guard wasRead else { return nil }
        let known = Set(older.map(\.id))
        let events = (older + aprs.events.filter { !known.contains($0.id) })
            .filter { filter.matches($0, ownCallsign: callsign) }
        return format.text(of: events.sorted { ($0.lastSeenMs, $0.id) < ($1.lastSeenMs, $1.id) })
    }

    public func deleteAPRSEvent(_ event: APRSEvent) {
        aprs.removeEvents { $0.id == event.id }
        for list in APRSList.allCases {
            self[list].older.removeAll { $0.id == event.id }
        }
        storedAPRSEvents[event.id] = nil
        withAPRSHistory { try await $0.delete(id: event.id) }
        showAPRS()
    }

    public func deleteAllAPRSEvents() {
        aprs.removeEvents { _ in true }
        for list in APRSList.allCases {
            self[list] = APRSListState(filter: aprsFilter(in: list))
        }
        storedAPRSEvents = [:]
        withAPRSHistory { try await $0.deleteAll() }
        showAPRS()
    }

    /// `ServiceAprsCallbacks.submitAprsIs`.
    private func gateAPRS(_ request: APRSInternetRequest) -> Bool {
        guard let internet, !callsign.isEmpty else { return false }
        return internet.send(request, as: callsign)
    }

    /// `updateAprsIsConnection`: connected while the iGate or the feed is on; sending only for the iGate.
    private func updateInternet() {
        let active = isIGateEnabled || isInternetFeedEnabled
        internet?.update(
            APRSISSettings(
                isEnabled: active && !callsign.isEmpty,
                isReceiveEnabled: isInternetFeedEnabled,
                isTransmitEnabled: isIGateEnabled,
                callsign: callsign,
                latitude: internetLocation?.latitude,
                longitude: internetLocation?.longitude
            )
        )
        isInternetConnected = internet?.isLoggedIn ?? false
    }

    /// `refreshAprsIsFilterLocation`: the feed shows packets around our position.
    private func locateInternetFilter(with location: any LocationProvider) async {
        guard let point = await location.currentLocation(), isInternetFeedEnabled else { return }
        ownPosition = point
        internetLocation = point
        updateInternet()
    }

    /// Memories changed on another device reach this one through the repository.
    private func observeMemories() {
        guard let repository else { return }
        let changes = repository.changes
        let finishedSyncs = repository.finishedSyncs
        memoryObservers = [
            Task { [weak self] in
                for await _ in changes {
                    await self?.loadMemories()
                }
            },
            Task { [weak self] in
                for await date in finishedSyncs {
                    self?.noteMemorySync(date)
                }
            },
        ]
    }

    private func noteMemorySync(_ date: Date) {
        lastMemorySync = max(lastMemorySync ?? date, date)
        saveSettings()
    }

    private func observeInternet() {
        guard let internet else { return }
        let received = internet.received
        let delivered = internet.delivered
        internetObservers = [
            Task { [weak self] in
                for await line in received {
                    self?.receiveInternet(line)
                }
            },
            Task { [weak self] in
                for await request in delivered {
                    self?.confirmInternet(request)
                }
            },
        ]
    }

    private func receiveInternet(_ line: String) {
        aprs.receive(internetLine: line, atMs: now())
        showAPRS()
    }

    private func confirmInternet(_ request: APRSInternetRequest) {
        aprs.recordInternetTransmission(request, atMs: now())
        showAPRS()
    }

    /// `ServiceAprsCallbacks.submitRf` with `AprsRfFrequencyPolicy`: only while receiving; a reliable message stays on
    /// its frequency, everything else goes out on the requested or current TX frequency, within the ham band.
    private func transmitAPRS(_ request: APRSTransmitRequest) -> APRSTransmitOutcome {
        guard canSendOnAir else { return .never }
        guard isReady, !isTransmitting, !isScanning, let controller, let firmware = snapshot.firmware else {
            return .later
        }
        let selected = Self.hertz(snapshot.desired.freqTx)
        let reliable = request.purpose == .outgoingMessage || request.purpose == .reliableMessageRetry
        if reliable, let requested = request.frequencyHz, requested != selected {
            return .never  // the app does not retune to the original frequency
        }
        let requested = request.purpose == .positionBeacon ? beaconOverride.map(Self.hertz) : request.frequencyHz
        let hertz: Int64
        switch (reliable, requested ?? request.frequencyHz) {
        case (false, let requested?): hertz = requested
        default: hertz = selected
        }
        let megahertz = Float(Double(hertz) / 1_000_000)
        guard txLimits.band(for: firmware.moduleType).allows(megahertz, bandwidth: snapshot.desired.bandwidth),
            let frame = try? request.packet.ax25Frame()
        else { return .later }
        Task { try? await controller.transmitAX25(frame, frequency: megahertz) }
        return .accepted(frequencyHz: hertz, frame: frame)
    }

    // MARK: Transmit

    /// `MainActivity.handlePttPress`: starts transmitting, or with sticky PTT toggles.
    public func pressPTT() async {
        guard isReady, let controller else { return }
        if isStickyPTT, isTransmitting {
            await controller.stopTransmitting()
        } else if canSendOnAir {
            isPTTHeld = true
            await otherAudio?.readyToTransmit()
            if isPTTHeld {
                await controller.setMicGain(micGain)
                do {
                    try await controller.startTransmitting()
                } catch {
                    refreshPermissions()
                    if isDenied(.microphone) {
                        message = Permission.microphone.deniedMessage
                    } else if error != .transmitNotAllowed {
                        message = Self.message(for: error)
                    }
                }
            }
        }
        show(await controller.snapshot)
        otherAudio?.endKeying()
    }

    /// `MainActivity.handlePttRelease`: ends the transmission unless PTT is sticky.
    public func releasePTT() async {
        guard !isStickyPTT, let controller else { return }
        isPTTHeld = false
        await controller.stopTransmitting()
        show(await controller.snapshot)
    }

    // MARK: Access tone

    private static let accessToneCutShort = "The tone was cut short, so the repeater may not have opened."
    private static let accessToneNotSent = "The radio did not start transmitting, so no tone went out."

    /// The tone that opens a repeater: the settings, and what the memory tuned to says instead (ADR-0045).
    public var accessTone: AccessTone? {
        let memory = memories.first { $0.id == activeMemoryId }
        let frequency = memory?.accessToneHz ?? accessToneHz
        guard frequency > 0 else { return nil }
        let length = memory?.accessToneLengthMs ?? accessToneLengthMs
        return AccessTone(frequency: frequency, lengthMs: length, waitMs: accessToneWaitMs)
    }

    public var canSendAccessTone: Bool {
        accessTone != nil && isReady && canSendOnAir && !isDenied(.microphone) && !isFreeDV
    }

    public var isSendingAccessTone: Bool { snapshot.isSendingAccessTone }

    /// Sends the tone, and returns when it is over.
    public func pressAccessTone() async {
        guard let controller, canSendOnAir, let tone = accessTone else { return }
        // What the last press reported no longer holds; another problem stays until dismissed.
        if message == Self.accessToneCutShort || message == Self.accessToneNotSent {
            message = nil
        }
        do {
            switch try await controller.sendAccessTone(tone) {
            case .finished: break
            case .stopped: message = Self.accessToneCutShort
            case .radioNotTransmitting: message = Self.accessToneNotSent
            }
        } catch {
            if error != .transmitNotAllowed { message = Self.message(for: error) }
        }
        show(await controller.snapshot)
    }

    /// A tone that is still going out ends at once; a finished one has nothing left to end.
    public func releaseAccessTone() async {
        guard let controller else { return }
        await controller.stopTransmitting()
        show(await controller.snapshot)
    }

    // MARK: Memories

    /// `makeSafeHamFreq` takes larger numbers for a mistyped decimal point; a memory must not hold one.
    private static let highestFrequency: Float = 500

    public var groups: [String] { ChannelMemory.groups(in: memories) }

    public var visibleMemories: [ChannelMemory] {
        guard let selectedGroup else { return memories }
        return memories.filter { $0.group == selectedGroup }
    }

    /// The memory the radio is tuned to.
    public var activeMemoryId: Int32? {
        let id = snapshot.desired.memoryId
        return isReady && id >= 0 ? id : nil
    }

    /// The name of the memory the radio is tuned to.
    public var activeMemoryName: String? {
        memories.first { $0.id == activeMemoryId }?.name
    }

    public var isScanning: Bool { snapshot.isScanning }

    /// Every memory by group, with those without a group as a block of their own.
    public var memoryBlocks: [MemoryGroup] { ChannelMemory.blocks(in: memories) }

    public func loadMemories() async {
        await store { _ in }
    }

    /// Adds a new memory (id 0) or replaces the one with the same id.
    public func save(_ memory: ChannelMemory) async {
        await store { repository in
            if memory.id == 0 {
                _ = try await repository.insert([memory])
            } else {
                try await repository.update(memory)
            }
        }
    }

    public func delete(_ memory: ChannelMemory) async {
        await delete([memory])
    }

    public func delete(_ memories: [ChannelMemory]) async {
        await store { repository in
            for memory in memories {
                try await repository.delete(id: memory.id)
            }
        }
    }

    /// Moves whole groups; `destination` is as in SwiftUI's `onMove`.
    public func moveGroups(_ offsets: IndexSet, to destination: Int) async {
        let order = ChannelMemory.order(ofBlocks: memoryBlocks, movingGroups: offsets, to: destination)
        await store { try await $0.reorder(order) }
    }

    /// Moves memories inside their group; `destination` is as in SwiftUI's `onMove`.
    public func moveMemories(inGroup group: String, _ offsets: IndexSet, to destination: Int) async {
        let order = ChannelMemory.order(ofBlocks: memoryBlocks, inGroup: group, moving: offsets, to: destination)
        await store { try await $0.reorder(order) }
    }

    /// Moves memories to the end of `group`.
    public func move(_ memories: [ChannelMemory], toGroup group: String) async {
        await store { repository in
            for var memory in memories {
                memory.group = group
                try await repository.update(memory)
            }
        }
    }

    /// Gives a group a new name; a name in use joins the two groups, a blank one changes nothing.
    public func renameGroup(_ group: String, to newName: String) async {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if selectedGroup == group {
            selectedGroup = name
        }
        await store { try await $0.renameGroup(group, to: name) }
    }

    /// Deletes a group with its memories, or keeps them without a group.
    public func deleteGroup(_ group: String, keepingMemories: Bool) async {
        let members = memories.filter { $0.group == group }
        if keepingMemories {
            await move(members, toGroup: "")
        } else {
            await delete(members)
        }
    }

    /// What keeps `memory` from being saved; `nil` if it can be.
    public func memoryProblem(_ memory: ChannelMemory) -> String? {
        if memory.name.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Enter a name."
        }
        guard memory.frequency.isFinite, memory.frequency > 0, memory.frequency <= Self.highestFrequency else {
            return "Enter a frequency in MHz."
        }
        if let firmware = snapshot.firmware, !(firmware.minRadioFreq...firmware.maxRadioFreq).contains(memory.frequency)
        {
            let lowest = HamFrequency.format(firmware.minRadioFreq)
            let highest = HamFrequency.format(firmware.maxRadioFreq)
            return "This radio receives from \(lowest) to \(highest) MHz."
        }
        return memory.offset != .none && memory.offsetKHz < 0 ? "Enter the offset in kHz." : nil
    }

    /// Where a memory with an offset transmits; the radio may still limit it when tuning.
    public func transmitText(for memory: ChannelMemory) -> String? {
        guard memory.offset != .none else { return nil }
        let frequency = memory.txFrequency(in: 0...Self.highestFrequency)
        return "Transmits on \(HamFrequency.format(frequency)) MHz"
    }

    public func tune(to memory: ChannelMemory) async {
        guard let controller else { return }
        try? await controller.tune(to: memory)
        show(await controller.snapshot)
    }

    /// Starts scanning the visible memories, or stops.
    public func toggleScan() async {
        guard let controller else { return }
        if isScanning {
            await controller.stopScan()
        } else {
            try? await controller.startScan(visibleMemories)
        }
        show(await controller.snapshot)
    }

    /// The app knows the radio's frequency range, which an import needs.
    public var canImportRepeaters: Bool { snapshot.firmware != nil }

    /// What importing a RepeaterBook CSV export into `group` would do; `nil` if the file is not one or no radio is known.
    public func importPreview(_ csv: String, group: String) -> RepeaterBookPreview? {
        guard let firmware = snapshot.firmware else { return nil }
        let range = firmware.minRadioFreq...firmware.maxRadioFreq
        return RepeaterBookImport.preview(fromCSV: csv, group: group, range: range, existing: memories)
    }

    /// Adds the repeaters of a RepeaterBook CSV export that the radio can receive and `group` does not have yet.
    public func importRepeaterBook(_ csv: String, group: String) async {
        guard canImportRepeaters else {
            message = "Connect the radio first, so that only repeaters it can receive are imported."
            return
        }
        guard let imported = importPreview(csv, group: group)?.memories else {
            message = "This file is not a RepeaterBook CSV export."
            return
        }
        await store { repository in
            _ = try await repository.insert(imported)
            message = "Imported \(imported.count) repeater\(imported.count == 1 ? "" : "s")."
            isNoticeSuccess = true
        }
    }

    /// Runs `change` and shows the stored memories afterwards.
    private func store(_ change: (any MemoryRepository) async throws -> Void) async {
        guard let repository else { return }
        do {
            try await change(repository)
            memories = try await repository.all()
            if let group = selectedGroup, !groups.contains(group) {
                selectedGroup = nil
            }
        } catch {
            message = "The memories could not be loaded or saved."
        }
    }

    // MARK: Settings

    /// Tunes RX and TX to the entered frequency, normalised and clamped like the Android app.
    public func applyFrequency() async {
        guard isReady, let controller, let firmware = snapshot.firmware, let current = frequency else { return }
        guard let entered = HamFrequency.safe(frequencyText, in: firmware.minRadioFreq...firmware.maxRadioFreq) else {
            message = "\"\(frequencyText)\" is not a frequency."
            frequencyText = HamFrequency.format(current)
            return
        }
        message = nil
        frequency = entered
        frequencyText = HamFrequency.format(entered)
        try? await controller.tune(rx: entered, tx: entered, memoryId: -1)
    }

    /// 25 kHz instead of 12.5 kHz.
    public var isWideBandwidth: Bool {
        get { snapshot.desired.bandwidth == 1 }
        set { update { $0.setBandwidth(newValue ? 1 : 0) } }
    }

    /// 0 (open) … 8.
    public var squelch: Int {
        get { Int(snapshot.desired.squelch) }
        set {
            let squelch = UInt8(clamping: newValue)
            update { $0.setSquelch(squelch) }
        }
    }

    /// Transmitting makes no use of the squelch, and a scan works with its own.
    public var canChangeSquelch: Bool { isReady && !isTransmitting && !isScanning }

    /// A change on the S-meter, or by VoiceOver; only while the squelch can change.
    public func changeSquelch(to level: Int) {
        guard canChangeSquelch else { return }
        squelch = min(max(level, SquelchMark.levels.lowerBound), SquelchMark.levels.upperBound)
    }

    /// A squelch of 0 sounds like a fault: noise without a signal.
    public var squelchWarning: String? {
        squelch == 0 ? "Squelch 0: the speaker is always on, also without a signal." : nil
    }

    public var isHighPower: Bool {
        get { snapshot.desired.flags.contains(.highPower) }
        set { update { $0.setHighPower(newValue) } }
    }

    /// The firmware offers FreeDV 2400B digital voice.
    public var supportsFreeDV: Bool { snapshot.supportsFreeDV }

    /// Voice mode: FreeDV 2400B instead of analog FM.
    public var isFreeDV: Bool {
        get { snapshot.isFreeDV }
        set {
            guard isReady, let controller else { return }
            Task { await controller.setFreeDV(newValue) }
        }
    }

    /// A label of `CTCSS.labels`.
    public var txTone: String {
        get { Self.label(snapshot.desired.ctcssTx) }
        set {
            let index = CTCSS.index(of: newValue)
            update { $0.setTxTone(index) }
        }
    }

    /// A label of `CTCSS.labels`.
    public var rxTone: String {
        get { Self.label(snapshot.desired.ctcssRx) }
        set {
            let index = CTCSS.index(of: newValue)
            update { $0.setRxTone(index) }
        }
    }

    public var filters: AudioFilters {
        get {
            let flags = snapshot.desired.flags
            return AudioFilters(
                preEmphasis: flags.contains(.filterPre),
                highPass: flags.contains(.filterHigh),
                lowPass: flags.contains(.filterLow)
            )
        }
        set { update { $0.setFilters(pre: newValue.preEmphasis, high: newValue.highPass, low: newValue.lowPass) } }
    }

    private func update(_ changes: @escaping @Sendable (inout DesiredStateController) -> Void) {
        guard isReady, let controller else { return }
        Task { await controller.update(changes) }
    }

    // MARK: Texts and rules

    static func statusText(for snapshot: RadioSnapshot) -> String {
        switch snapshot.status {
        case .disconnected: "Not connected"
        case .connecting: "Connecting…"
        case .waitingForHello: "Waiting for the radio…"
        case .ready: snapshot.isInSync ? "Connected" : "Connected, applying settings…"
        case .failed(let failure): message(for: failure)
        }
    }

    static func message(for failure: RadioFailure) -> String {
        switch failure {
        case .helloTimeout: "The radio did not answer. Check that it is on and has the firmware for this app."
        case .invalidHello: "The firmware of the radio is too old. Update it to the firmware for this app."
        case .firmwareTooOld(let version): "Firmware \(version) is too old. Update it to the firmware for this app."
        case .firmwareForAndroid:
            "This radio has the firmware for the Android app, with which this app has no sound. "
                + "Update it to the firmware for this app."
        case .radioModuleNotFound: "The SA818 radio module did not respond. Restart the radio."
        case .transport(let error): message(for: error)
        }
    }

    static func message(for error: FlashError) -> String {
        switch error {
        case .noAnswer: "The radio did not start its bootloader. Check the USB cable and try again."
        case .unsupportedChip: "This device is not a kv4p HT."
        case .verifyFailed: "The firmware could not be verified. Start the update again."
        case .port(let error): message(for: error)
        case .timeout, .commandFailed, .stubNotStarted:
            "The radio stopped answering during the update. Start the update again; it can always be repeated."
        }
    }

    static func message(for error: RadioError) -> String {
        switch error {
        case .transmitNotAllowed: "Can't transmit outside the ham band."
        case .microphoneUnavailable:
            "The microphone could not be started. Press PTT again."
        case .notReady, .frequencyOutOfRange: "The radio is not ready."
        case .busy: "The radio is busy transmitting or scanning."
        case .invalidPacket: "The packet cannot be sent."
        }
    }

    private static func message(for error: TransportError) -> String {
        switch error {
        case .bluetoothUnavailable(.unauthorized):
            "Bluetooth access is not allowed. Allow it under Privacy & Security → Bluetooth in the settings."
        case .bluetoothUnavailable(.poweredOff): "Bluetooth is off."
        case .bluetoothUnavailable: "Bluetooth is not available."
        case .serviceNotFound:
            "This device is not a kv4p HT, or its firmware has no Bluetooth LE service. "
                + "Update it to the firmware for this app."
        case .connectionLost: "The connection to the radio was lost."
        case .portUnavailable(let path, _): "\(path) cannot be opened."
        default: "The connection failed."
        }
    }

    /// `S0`…`S9`, then 20 dB steps (`S9+20`…`S9+60`), then `Overload` (`SMeter.overload`).
    static func sMeterText(for value: Int) -> String {
        switch value {
        case SMeter.overload: "Overload"
        case 10...: "S9+\((value - 9) * 20)"
        default: "S\(value)"
        }
    }

    private static func label(_ tone: UInt8) -> String {
        CTCSS.label(for: tone) ?? CTCSS.none
    }
}

/// The two views of the APRS list: each has its own filter, so that looking through the history in the settings does not
/// hide new packets on the main page.
public enum APRSList: CaseIterable, Hashable, Sendable {
    case main, packetsPage
}

private struct APRSListState {
    var filter = APRSListFilter()
    /// Older packets the user has brought back to this list.
    var older: [APRSEvent] = []
    /// How far back they go.
    var cursor: Int64?
    var hasMore = false
    var events: [APRSEvent] = []
}
