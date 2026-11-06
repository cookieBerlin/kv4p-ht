import Foundation

/// iCloud's key-value store: forwards only (ADR-0018, ADR-0051).
public final class UbiquitousSettingsStore: SyncedSettingsStore, @unchecked Sendable {
    // NSUbiquitousKeyValueStore is thread-safe.
    private let store = NSUbiquitousKeyValueStore.default

    public init() {
        store.synchronize()
    }

    public var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    public func values() -> [String: Data] {
        store.dictionaryRepresentation.compactMapValues { $0 as? Data }
    }

    public func set(_ values: [String: Data]) {
        for (key, value) in values {
            store.set(value, forKey: key)
        }
        store.synchronize()
    }

    public func observeChanges(_ onChange: @escaping @Sendable () -> Void) {
        _ = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: nil
        ) { _ in onChange() }
    }
}
