import Foundation

/// Keeps the encoded app settings between launches (Android `AppSetting` rows).
public protocol SettingsStore: Sendable {
    func load() -> Data?
    func save(_ data: Data)
}

/// The settings that follow the user to their other devices, one value per key (ADR-0051).
public protocol SyncedSettingsStore: Sendable {
    /// iCloud is signed in; without it the values stay on this device.
    var isAvailable: Bool { get }
    func values() -> [String: Data]
    func set(_ values: [String: Data])
    /// Another device changed something, or the account changed.
    func observeChanges(_ onChange: @escaping @Sendable () -> Void)
}

/// The settings in the user defaults, under one key.
public struct UserDefaultsSettingsStore: SettingsStore, @unchecked Sendable {
    // UserDefaults is thread-safe.
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "settings") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> Data? {
        defaults.data(forKey: key)
    }

    public func save(_ data: Data) {
        defaults.set(data, forKey: key)
    }
}
