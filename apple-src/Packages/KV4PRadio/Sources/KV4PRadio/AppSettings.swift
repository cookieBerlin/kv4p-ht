import Foundation
import KV4PAPRS
import KV4PAudio
import KV4PTransport

/// The settings of the app itself (Android `AppSetting`); the radio keeps its own configuration.
public struct AppSettings: Codable, Equatable, Sendable {
    public var callsign = ""
    public var micGain = MicGain.none
    public var isStickyPTT = false
    public var isBeaconEnabled = false
    public var beaconSymbol = APRSSymbol.phone
    public var isBeaconApproximate = false
    /// MHz; `nil` beacons on the current TX frequency (Android "Current").
    public var beaconFrequency: Float?
    public var isDigipeatingEnabled = false
    public var isIGateEnabled = false
    public var isInternetFeedEnabled = false
    public var aprsDestinationFilter = APRSDestinationFilter.all
    public var txLimits = TXLimits()
    /// The memory group shown (`lastGroup`); `nil` for all.
    public var selectedGroup: String?
    /// The radio chosen over Bluetooth; `nil` for the first one found (ADR-0038).
    public var bluetoothRadio: BLEDevice?

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
        micGain = values.value(.micGain, or: defaults.micGain)
        isStickyPTT = values.value(.isStickyPTT, or: defaults.isStickyPTT)
        isBeaconEnabled = values.value(.isBeaconEnabled, or: defaults.isBeaconEnabled)
        beaconSymbol = values.value(.beaconSymbol, or: defaults.beaconSymbol)
        isBeaconApproximate = values.value(.isBeaconApproximate, or: defaults.isBeaconApproximate)
        beaconFrequency = values.value(.beaconFrequency, or: defaults.beaconFrequency)
        isDigipeatingEnabled = values.value(.isDigipeatingEnabled, or: defaults.isDigipeatingEnabled)
        isIGateEnabled = values.value(.isIGateEnabled, or: defaults.isIGateEnabled)
        isInternetFeedEnabled = values.value(.isInternetFeedEnabled, or: defaults.isInternetFeedEnabled)
        aprsDestinationFilter = values.value(.aprsDestinationFilter, or: defaults.aprsDestinationFilter)
        txLimits = values.value(.txLimits, or: defaults.txLimits)
        selectedGroup = values.value(.selectedGroup, or: defaults.selectedGroup)
        bluetoothRadio = values.value(.bluetoothRadio, or: defaults.bluetoothRadio)
    }
}

extension KeyedDecodingContainer {
    /// The value for `key`, or `fallback` if it is missing or cannot be decoded.
    fileprivate func value<T: Decodable>(_ key: Key, or fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)).flatMap { $0 } ?? fallback
    }
}
