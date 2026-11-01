import Foundation
import Testing

@testable import KV4PPersistence

@Suite("Settings store")
struct SettingsStoreTests {
    @Test("settings are kept in the user defaults under one key")
    func userDefaults() throws {
        let suite = "kv4p.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsSettingsStore(defaults: defaults, key: "settings")
        #expect(store.load() == nil)
        store.save(Data([1, 2]))
        #expect(store.load() == Data([1, 2]))
        #expect(UserDefaultsSettingsStore(defaults: defaults, key: "settings").load() == Data([1, 2]))
    }
}
