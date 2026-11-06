import Foundation
import KV4PAPRS
import KV4PAudio
import KV4PSimulator
import KV4PTransport

/// How accurately a position beacon reports the position; Android offers exact and the 0.01° of 1000 m.
public enum BeaconAccuracy: String, Codable, CaseIterable, Sendable {
    case exact, within50m, within100m, within500m, within1000m

    public var label: String {
        switch self {
        case .exact: "Exact"
        case .within50m: "50 m"
        case .within100m: "100 m"
        case .within500m: "500 m"
        case .within1000m: "1000 m"
        }
    }

    /// Rounds a latitude or longitude to steps of 0.0005° to 0.01°, about the distance named.
    public func rounded(_ degrees: Double) -> Double {
        let stepsPerDegree: Double
        switch self {
        case .exact: return degrees
        case .within50m: stepsPerDegree = 2000
        case .within100m: stepsPerDegree = 1000
        case .within500m: stepsPerDegree = 200
        case .within1000m: stepsPerDegree = 100
        }
        return (degrees * stepsPerDegree + 0.5).rounded(.down) / stepsPerDegree
    }
}

/// The settings of the app itself (Android `AppSetting`); the radio keeps its own configuration.
public struct AppSettings: Codable, Equatable, Sendable {
    public var callsign = ""
    /// The app does not transmit, by the user's choice (ADR-0047).
    public var isListenOnly = false
    /// The settings for all devices follow the user through iCloud (ADR-0051).
    public var isSettingsSyncEnabled = true
    /// When this device last exchanged settings with iCloud.
    public var lastSettingsSync: Date?
    /// When a sync of the memories with iCloud last finished.
    public var lastMemorySync: Date?
    public var micGain = MicGain.none
    public var isStickyPTT = false
    /// The tone that opens a repeater, in Hz; 0 for none (ADR-0045).
    public var accessToneHz = 0
    public var accessToneLengthMs = AccessTone.defaultLengthMs
    public var accessToneWaitMs = AccessTone.defaultWaitMs
    /// What other apps do while the radio is busy; local to the device, also for settings sync (3.8).
    public var otherAudioMode = OtherAudioMode.pausePodcasts
    /// How long the squelch stays closed before other apps return.
    public var otherAudioResumeSeconds = 3
    public var isBeaconEnabled = false
    public var beaconSymbol = APRSSymbol.phone
    public var beaconAccuracy = BeaconAccuracy.exact
    /// How often the beacon goes out (ADR-0056).
    public var beaconIntervalMinutes = 5
    /// The beacon goes on with the screen locked; local to the device (ADR-0056).
    public var isBackgroundBeaconEnabled = true
    /// MHz; `nil` beacons on the current TX frequency (Android "Current").
    public var beaconFrequency: Float?
    public var isDigipeatingEnabled = false
    public var isIGateEnabled = false
    public var isInternetFeedEnabled = false
    /// What the list on the main page looks for; local to the device (ADR-0057).
    public var aprsListFilter = APRSListFilter()
    /// What the packets page of the settings looks for; local to the device.
    public var aprsPageFilter = APRSListFilter()
    /// The list stays across restarts; local to the device, as the packets are (ADR-0057).
    public var isKeepingPackets = true
    /// Packets only from the internet are stored as well, which can be many.
    public var keepsInternetPackets = false
    /// How long packets stay, in days; 0 for without limit.
    public var packetRetentionDays = 30
    /// A message to this station in the background brings a notification; local to the device (ADR-0058).
    public var notifiesAboutMessages = true
    /// The units of the APRS list (ADR-0055).
    public var units = APRSUnits.system
    public var txLimits = TXLimits()
    /// The memory group shown (`lastGroup`); `nil` for all.
    public var selectedGroup: String?
    /// The radio chosen over Bluetooth; `nil` for the first one found (ADR-0038).
    public var bluetoothRadio: BLEDevice?
    /// The simulator was the chosen radio, so the next start has it chosen again.
    public var isSimulatorChosen = false
    /// How the simulated radio behaves, for testing; local to the device (ADR-0041).
    public var simulator = SimulatorSettings()

    /// Days, with 0 for without limit.
    public static let packetRetentionOptions = [1, 7, 30, 0]

    /// All stations share the APRS frequency, so there is no shorter one.
    public static let beaconIntervalOptions = [2, 5, 10, 15, 30, 60]

    /// `SettingsActivity.populateAprsFrequencies`, after "Current".
    public static let beaconFrequencyOptions: [Float] = [144.39, 144.575, 144.64, 144.66, 144.8, 145.175, 145.825]

    public init() {}

    /// Decodes stored settings; values that are missing or unreadable keep their defaults.
    public init(data: Data?) {
        self = data.flatMap { try? JSONDecoder().decode(AppSettings.self, from: $0) } ?? AppSettings()
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        callsign = values.value(.callsign, or: defaults.callsign)
        isListenOnly = values.value(.isListenOnly, or: defaults.isListenOnly)
        isSettingsSyncEnabled = values.value(.isSettingsSyncEnabled, or: defaults.isSettingsSyncEnabled)
        lastSettingsSync = values.value(.lastSettingsSync, or: defaults.lastSettingsSync)
        lastMemorySync = values.value(.lastMemorySync, or: defaults.lastMemorySync)
        micGain = values.value(.micGain, or: defaults.micGain)
        isStickyPTT = values.value(.isStickyPTT, or: defaults.isStickyPTT)
        accessToneHz = values.value(.accessToneHz, or: defaults.accessToneHz)
        accessToneLengthMs = values.value(.accessToneLengthMs, or: defaults.accessToneLengthMs)
        accessToneWaitMs = values.value(.accessToneWaitMs, or: defaults.accessToneWaitMs)
        otherAudioMode = values.value(.otherAudioMode, or: defaults.otherAudioMode)
        otherAudioResumeSeconds = values.value(.otherAudioResumeSeconds, or: defaults.otherAudioResumeSeconds)
        isBeaconEnabled = values.value(.isBeaconEnabled, or: defaults.isBeaconEnabled)
        beaconSymbol = values.value(.beaconSymbol, or: defaults.beaconSymbol)
        let former = try decoder.container(keyedBy: FormerKeys.self)
        let wasApproximate = (try? former.decodeIfPresent(Bool.self, forKey: .isBeaconApproximate)) == true
        beaconAccuracy = values.value(.beaconAccuracy, or: wasApproximate ? .within1000m : defaults.beaconAccuracy)
        beaconFrequency = values.value(.beaconFrequency, or: defaults.beaconFrequency)
        beaconIntervalMinutes = values.value(.beaconIntervalMinutes, or: defaults.beaconIntervalMinutes)
        isBackgroundBeaconEnabled = values.value(.isBackgroundBeaconEnabled, or: defaults.isBackgroundBeaconEnabled)
        isDigipeatingEnabled = values.value(.isDigipeatingEnabled, or: defaults.isDigipeatingEnabled)
        isIGateEnabled = values.value(.isIGateEnabled, or: defaults.isIGateEnabled)
        isInternetFeedEnabled = values.value(.isInternetFeedEnabled, or: defaults.isInternetFeedEnabled)
        aprsListFilter = values.value(.aprsListFilter, or: defaults.aprsListFilter)
        aprsPageFilter = values.value(.aprsPageFilter, or: defaults.aprsPageFilter)
        units = values.value(.units, or: defaults.units)
        isKeepingPackets = values.value(.isKeepingPackets, or: defaults.isKeepingPackets)
        keepsInternetPackets = values.value(.keepsInternetPackets, or: defaults.keepsInternetPackets)
        packetRetentionDays = values.value(.packetRetentionDays, or: defaults.packetRetentionDays)
        notifiesAboutMessages = values.value(.notifiesAboutMessages, or: defaults.notifiesAboutMessages)
        txLimits = values.value(.txLimits, or: defaults.txLimits)
        selectedGroup = values.value(.selectedGroup, or: defaults.selectedGroup)
        bluetoothRadio = values.value(.bluetoothRadio, or: defaults.bluetoothRadio)
        isSimulatorChosen = values.value(.isSimulatorChosen, or: defaults.isSimulatorChosen)
        simulator = values.value(.simulator, or: defaults.simulator)
    }

    /// Settings stored by earlier versions.
    private enum FormerKeys: String, CodingKey {
        case isBeaconApproximate
    }
}

extension KeyedDecodingContainer {
    /// The value for `key`, or `fallback` if it is missing or cannot be decoded.
    fileprivate func value<T: Decodable>(_ key: Key, or fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)).flatMap { $0 } ?? fallback
    }
}
