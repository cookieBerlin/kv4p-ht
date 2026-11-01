import Foundation

/// Keeps the encoded app settings between launches (Android `AppSetting` rows).
public protocol SettingsStore: Sendable {
    func load() -> Data?
    func save(_ data: Data)
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
