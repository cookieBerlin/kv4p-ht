import Foundation

/// Which settings follow the user to their other devices, and what to send and take (ADR-0051). Each setting is a value
/// of its own, so that changes of different settings on two devices do not get in each other's way.
struct SettingsSync {
    /// What this device and the cloud last agreed on.
    private var agreed: [String: Data]

    init(_ settings: AppSettings) {
        agreed = Self.values(of: settings)
    }

    static func values(of settings: AppSettings) -> [String: Data] {
        fields.reduce(into: [:]) { values, field in values[field.key] = field.read(settings) }
    }

    /// What this device knows and the cloud does not, so that a device that has the settings already does not start
    /// over; a default says nothing, so a new device leaves others alone.
    static func unknownToCloud(_ settings: AppSettings, remote: [String: Data]) -> [String: Data] {
        let defaults = values(of: AppSettings())
        return values(of: settings).filter { remote[$0.key] == nil && $0.value != defaults[$0.key] }
    }

    /// What changed here since the last agreement; that is the agreement from now on.
    mutating func outgoing(_ settings: AppSettings) -> [String: Data] {
        let changed = Self.values(of: settings).filter { agreed[$0.key] != $0.value }
        agreed.merge(changed) { $1 }
        return changed
    }

    /// The settings with what the cloud has changed. A change that waits here to be sent is newer, and stays.
    mutating func incoming(_ remote: [String: Data], into settings: AppSettings) -> AppSettings {
        let current = Self.values(of: settings)
        var merged = settings
        for field in Self.fields {
            guard let value = remote[field.key], value != agreed[field.key], current[field.key] == agreed[field.key]
            else { continue }
            if field.write(&merged, value) {
                agreed[field.key] = value
            }
        }
        return merged
    }

    private struct Field {
        let key: String
        let read: (AppSettings) -> Data?
        let write: (inout AppSettings, Data) -> Bool

        init<Value: Codable>(_ key: String, _ path: WritableKeyPath<AppSettings, Value>) {
            self.key = key
            read = { settings in
                // Without a fixed order, a value with several fields would look changed from time to time.
                let encoder = JSONEncoder()
                encoder.outputFormatting = .sortedKeys
                return try? encoder.encode(settings[keyPath: path])
            }
            write = { settings, data in
                guard let value = try? JSONDecoder().decode(Value.self, from: data) else { return false }
                settings[keyPath: path] = value
                return true
            }
        }
    }

    /// The same for every device of a user; what belongs to one device stays out: the radio, the simulator, the memory
    /// group, other audio, mic gain, listen only and the switches that make the app send.
    private static var fields: [Field] {
        [
            Field("callsign", \.callsign),
            Field("isStickyPTT", \.isStickyPTT),
            Field("accessToneHz", \.accessToneHz),
            Field("accessToneLengthMs", \.accessToneLengthMs),
            Field("accessToneWaitMs", \.accessToneWaitMs),
            Field("beaconSymbol", \.beaconSymbol),
            Field("beaconAccuracy", \.beaconAccuracy),
            Field("beaconFrequency", \.beaconFrequency),
            Field("beaconIntervalMinutes", \.beaconIntervalMinutes),
            Field("aprsDestinationFilter", \.aprsDestinationFilter),
            Field("txLimits", \.txLimits),
            Field("units", \.units),
        ]
    }
}
