import Foundation
import KV4PAPRS
import KV4PPersistence
import KV4PSimulator
import KV4PTestSupport
import Synchronization
import Testing

@testable import KV4PRadio

/// iCloud in memory, shared between the models that stand for two devices.
final class MemorySyncedSettings: SyncedSettingsStore {
    private struct State {
        var values: [String: Data] = [:]
        var writes: [[String: Data]] = []
        var observers: [@Sendable () -> Void] = []
        var isAvailable = true
    }

    private let state = Mutex(State())

    var isAvailable: Bool {
        get { state.withLock { $0.isAvailable } }
        set { state.withLock { $0.isAvailable = newValue } }
    }

    var writes: [[String: Data]] { state.withLock { $0.writes } }

    func values() -> [String: Data] {
        state.withLock { $0.values }
    }

    func set(_ values: [String: Data]) {
        state.withLock {
            $0.values.merge(values) { $1 }
            $0.writes.append(values)
        }
    }

    func observeChanges(_ onChange: @escaping @Sendable () -> Void) {
        state.withLock { $0.observers.append(onChange) }
    }

    /// Another device wrote these, and the change arrives here.
    func receive(_ settings: AppSettings, keys: [String]) {
        let observers = state.withLock { state in
            let values = SettingsSync.values(of: settings)
            for key in keys { state.values[key] = values[key] }
            return state.observers
        }
        observers.forEach { $0() }
    }
}

/// The settings that follow the user to their other devices (ADR-0051).
@MainActor
@Suite("Settings sync")
struct SettingsSyncTests {
    private static func model(
        _ cloud: MemorySyncedSettings,
        local: AppSettings? = nil,
        store: MemorySettingsStore? = nil,
        time: TestTime = TestTime(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { _ in }
    ) -> RadioViewModel {
        RadioViewModel(
            makeController: { _, _ in RadioController(transport: ScriptedTransport()) },
            serialDevices: { [] },
            settings: store ?? MemorySettingsStore(local),
            syncedSettings: cloud,
            settingsSyncSleep: sleep,
            now: { time.ms }
        )
    }

    private static func date(_ time: TestTime) -> Date {
        Date(timeIntervalSince1970: Double(time.ms) / 1000)
    }

    private static func settled(_ cloud: MemorySyncedSettings, writes: Int) async -> Bool {
        for _ in 0..<500 {
            if cloud.writes.count >= writes { return true }
            await Task.yield()
        }
        return false
    }

    @Test("the settings for all devices are synced, those of this device are not")
    func keys() {
        #expect(
            Set(SettingsSync.values(of: AppSettings()).keys) == [
                "callsign", "isStickyPTT", "accessToneHz", "accessToneLengthMs", "accessToneWaitMs", "beaconSymbol",
                "beaconAccuracy", "beaconFrequency", "aprsDestinationFilter", "txLimits",
            ]
        )
    }

    @Test("the same settings always give the same values, or they would look changed")
    func stable() {
        let first = SettingsSync.values(of: AppSettings())
        for _ in 0..<50 {
            #expect(SettingsSync.values(of: AppSettings()) == first)
        }
    }

    @Test("a value survives the way through the cloud, also no beacon frequency")
    func roundTrip() {
        var settings = AppSettings()
        settings.callsign = "N0CALL"
        settings.beaconFrequency = 144.39
        settings.beaconSymbol = .car
        var sync = SettingsSync(AppSettings())
        #expect(sync.incoming(SettingsSync.values(of: settings), into: AppSettings()).callsign == "N0CALL")
        settings.beaconFrequency = nil
        var withFrequency = AppSettings()
        withFrequency.beaconFrequency = 144.8
        var other = SettingsSync(withFrequency)
        let merged = other.incoming(SettingsSync.values(of: settings), into: withFrequency)
        #expect(merged.beaconFrequency == nil)
        #expect(merged.beaconSymbol == .car)
    }

    @Test("an unreadable value from another version is left out")
    func unreadable() {
        var sync = SettingsSync(AppSettings())
        let merged = sync.incoming(["isStickyPTT": Data("not json".utf8)], into: AppSettings())
        #expect(merged == AppSettings())
    }

    @Test("a new empty device writes nothing, and takes what the cloud has")
    func newDevice() async {
        let cloud = MemorySyncedSettings()
        var other = AppSettings()
        other.callsign = "N0CALL"
        other.isStickyPTT = true
        cloud.set(SettingsSync.values(of: other))
        let writes = cloud.writes.count
        let model = Self.model(cloud)
        #expect(model.callsign == "N0CALL")
        #expect(model.isStickyPTT)
        #expect(!model.isStationSetupPending)
        await Task.yield()
        #expect(cloud.writes.count == writes)
    }

    @Test("what this device had before the cloud knew it goes up once, but no default")
    func firstRun() {
        let cloud = MemorySyncedSettings()
        var local = AppSettings()
        local.callsign = "N0CALL"
        _ = Self.model(cloud, local: local)
        #expect(cloud.writes.count == 1)
        #expect(cloud.writes.first?.keys.sorted() == ["callsign"])
    }

    @Test("a change by the user goes up after a pause, only what changed")
    func change() async {
        let cloud = MemorySyncedSettings()
        let model = Self.model(cloud)
        model.isStickyPTT = true
        #expect(await Self.settled(cloud, writes: 1))
        #expect(cloud.writes.first?.keys.sorted() == ["isStickyPTT"])
    }

    @Test("a change of several in a row goes up as one write")
    func debounce() async {
        let cloud = MemorySyncedSettings()
        let gate = AsyncStream<Void>.makeStream()
        let waits = Mutex(0)
        let model = Self.model(cloud) { _ in
            let wait = waits.withLock {
                $0 += 1
                return $0
            }
            if wait == 1 { try await Task.sleep(for: .seconds(60)) }
            for await _ in gate.stream { break }
        }
        model.callsign = "N0CALL"
        model.isStickyPTT = true
        await Task.yield()
        gate.continuation.yield()
        #expect(await Self.settled(cloud, writes: 1))
        #expect(cloud.writes.first?.keys.sorted() == ["callsign", "isStickyPTT"])
    }

    @Test("leaving the app sends at once what still waits")
    func flush() {
        let cloud = MemorySyncedSettings()
        let model = Self.model(cloud) { _ in try await Task.sleep(for: .seconds(60)) }
        model.flushSettingsSync()
        #expect(cloud.writes.isEmpty)
        model.isStickyPTT = true
        model.flushSettingsSync()
        #expect(cloud.writes.first?.keys.sorted() == ["isStickyPTT"])
    }

    @Test("a change that does not concern other devices writes nothing")
    func localChange() {
        let cloud = MemorySyncedSettings()
        let model = Self.model(cloud) { _ in try await Task.sleep(for: .seconds(60)) }
        model.isListenOnly = true
        model.micGain = .high
        model.isBeaconEnabled = true
        model.flushSettingsSync()
        #expect(cloud.writes.isEmpty)
    }

    @Test("a change from another device arrives, is stored and is not sent back")
    func incoming() async {
        let cloud = MemorySyncedSettings()
        let store = MemorySettingsStore()
        let model = Self.model(cloud, store: store) { _ in try await Task.sleep(for: .seconds(60)) }
        var other = AppSettings()
        other.isStickyPTT = true
        other.beaconSymbol = .car
        cloud.receive(other, keys: ["isStickyPTT", "beaconSymbol"])
        #expect(await RadioViewModelTests.eventually(model) { $0.isStickyPTT })
        #expect(model.beaconSymbol == .car)
        #expect(store.settings.isStickyPTT)
        model.flushSettingsSync()
        #expect(cloud.writes.isEmpty)
    }

    @Test("an incoming callsign closes the question at the start, its removal does not open it")
    func stationSetup() async {
        let cloud = MemorySyncedSettings()
        let model = Self.model(cloud) { _ in try await Task.sleep(for: .seconds(60)) }
        #expect(model.isStationSetupPending)
        var other = AppSettings()
        other.callsign = "N0CALL"
        cloud.receive(other, keys: ["callsign"])
        #expect(await RadioViewModelTests.eventually(model) { !$0.isStationSetupPending })
        #expect(model.callsign == "N0CALL")
        cloud.receive(AppSettings(), keys: ["callsign"])
        #expect(await RadioViewModelTests.eventually(model) { $0.callsign.isEmpty })
        #expect(!model.isStationSetupPending)
    }

    @Test("a change waiting here wins over one that arrives")
    func localWins() {
        let cloud = MemorySyncedSettings()
        var local = AppSettings()
        local.beaconSymbol = .house
        var sync = SettingsSync(local)
        var changed = local
        changed.beaconSymbol = .car
        var other = local
        other.beaconSymbol = .bicycle
        other.isStickyPTT = true
        let merged = sync.incoming(SettingsSync.values(of: other), into: changed)
        #expect(merged.beaconSymbol == .car)
        #expect(merged.isStickyPTT)
        #expect(sync.outgoing(merged).keys.sorted() == ["beaconSymbol"])
        #expect(cloud.writes.isEmpty)
    }

    @Test("switched off, nothing goes up and nothing arrives; switched on, it catches up")
    func switchedOff() async {
        let cloud = MemorySyncedSettings()
        let store = MemorySettingsStore()
        let model = Self.model(cloud, store: store) { _ in try await Task.sleep(for: .seconds(60)) }
        #expect(model.isSettingsSyncEnabled)
        model.isStickyPTT = true
        model.isSettingsSyncEnabled = false
        #expect(!store.settings.isSettingsSyncEnabled)
        model.flushSettingsSync()
        #expect(cloud.writes.isEmpty)
        var other = AppSettings()
        other.callsign = "N0CALL"
        cloud.receive(other, keys: ["callsign"])
        await Task.yield()
        await Task.yield()
        #expect(model.callsign.isEmpty)
        model.isSettingsSyncEnabled = true
        #expect(model.callsign == "N0CALL")
    }

    @Test("switched off at the start, the cloud stays out")
    func offAtStart() {
        let cloud = MemorySyncedSettings()
        var other = AppSettings()
        other.callsign = "N0CALL"
        cloud.set(SettingsSync.values(of: other))
        var local = AppSettings()
        local.isSettingsSyncEnabled = false
        let model = Self.model(cloud, local: local)
        #expect(model.callsign.isEmpty)
    }

    @Test("without iCloud a hint says so, and the app goes on as before")
    func noICloud() {
        let cloud = MemorySyncedSettings()
        cloud.isAvailable = false
        let model = Self.model(cloud)
        #expect(model.settingsSyncHint != nil)
        model.isSettingsSyncEnabled = false
        #expect(model.settingsSyncHint == nil)
        model.isSettingsSyncEnabled = true
        cloud.isAvailable = true
        model.isSettingsSyncEnabled = false
        model.isSettingsSyncEnabled = true
        #expect(model.settingsSyncHint == nil)
    }

    @Test("without a store for it, a model has no sync and no hint")
    func noStore() {
        let model = RadioViewModel(
            makeController: { _, _ in RadioController(transport: ScriptedTransport()) },
            serialDevices: { [] }
        )
        model.isStickyPTT = true
        model.flushSettingsSync()
        #expect(model.settingsSyncHint == nil)
    }

    @Test("sending and receiving note the time, a change for this device alone does not")
    func lastSync() async {
        let cloud = MemorySyncedSettings()
        let store = MemorySettingsStore()
        let time = TestTime()
        time.advance(by: 5_000)
        let model = Self.model(cloud, store: store, time: time) { _ in try await Task.sleep(for: .seconds(60)) }
        #expect(model.lastSettingsSync == nil)
        model.micGain = .high
        model.flushSettingsSync()
        #expect(model.lastSettingsSync == nil)
        model.isStickyPTT = true
        model.flushSettingsSync()
        #expect(model.lastSettingsSync == Self.date(time))
        #expect(store.settings.lastSettingsSync == model.lastSettingsSync)
        time.advance(by: 9_000)
        var other = model.settings
        other.beaconSymbol = .car
        cloud.receive(other, keys: ["beaconSymbol"])
        #expect(await RadioViewModelTests.eventually(model) { $0.beaconSymbol == .car })
        #expect(model.lastSettingsSync == Self.date(time))
    }

    @Test("a notice from the cloud without a change also counts as a sync")
    func lastSyncWithoutChange() async {
        let cloud = MemorySyncedSettings()
        let time = TestTime()
        time.advance(by: 7_000)
        let model = Self.model(cloud, time: time)
        cloud.receive(AppSettings(), keys: [])
        #expect(await RadioViewModelTests.eventually(model) { $0.lastSettingsSync != nil })
    }

    @Test("values taken or sent at the start count as a sync, nothing to do does not")
    func lastSyncAtStart() {
        let time = TestTime()
        time.advance(by: 3_000)
        #expect(Self.model(MemorySyncedSettings(), time: time).lastSettingsSync == nil)
        var other = AppSettings()
        other.callsign = "N0CALL"
        let cloud = MemorySyncedSettings()
        cloud.set(SettingsSync.values(of: other))
        #expect(Self.model(cloud, time: time).lastSettingsSync == Self.date(time))
        #expect(Self.model(MemorySyncedSettings(), local: other, time: time).lastSettingsSync != nil)
    }

    @Test("without iCloud nothing counts as synced, and the last time is kept across a restart")
    func lastSyncWithoutICloud() {
        let cloud = MemorySyncedSettings()
        cloud.isAvailable = false
        let model = Self.model(cloud) { _ in try await Task.sleep(for: .seconds(60)) }
        model.isStickyPTT = true
        model.flushSettingsSync()
        #expect(model.lastSettingsSync == nil)
        var local = AppSettings()
        local.lastSettingsSync = Date(timeIntervalSince1970: 11)
        #expect(Self.model(MemorySyncedSettings(), local: local).lastSettingsSync == Date(timeIntervalSince1970: 11))
    }

    @Test("the time of the last memory sync is shown and kept, and does not go back")
    func lastMemorySync() async {
        struct Syncing: MemoryRepository {
            let times: AsyncStream<Date>
            var finishedSyncs: AsyncStream<Date> { times }
            func all() async throws -> [ChannelMemory] { [] }
            func insert(_ memories: [ChannelMemory]) async throws -> [ChannelMemory] { memories }
            func update(_ memory: ChannelMemory) async throws {}
            func delete(id: Int32) async throws {}
            func reorder(_ ids: [Int32]) async throws {}
            func renameGroup(_ group: String, to newName: String) async throws {}
        }
        let (times, continuation) = AsyncStream.makeStream(of: Date.self)
        let store = MemorySettingsStore()
        var local = AppSettings()
        local.lastMemorySync = Date(timeIntervalSince1970: 10)
        store.save((try? local.encoded()) ?? Data())
        let model = RadioViewModel(
            makeController: { _, _ in RadioController(transport: ScriptedTransport()) },
            serialDevices: { [] },
            memories: Syncing(times: times),
            settings: store
        )
        #expect(model.lastMemorySync == Date(timeIntervalSince1970: 10))
        continuation.yield(Date(timeIntervalSince1970: 20))
        #expect(await RadioViewModelTests.eventually(model) { $0.lastMemorySync == Date(timeIntervalSince1970: 20) })
        #expect(store.settings.lastMemorySync == Date(timeIntervalSince1970: 20))
        continuation.yield(Date(timeIntervalSince1970: 15))
        continuation.yield(Date(timeIntervalSince1970: 30))
        #expect(await RadioViewModelTests.eventually(model) { $0.lastMemorySync == Date(timeIntervalSince1970: 30) })
        #expect(!SettingsSync.values(of: AppSettings()).keys.contains("lastMemorySync"))
    }

    @Test("a real wait is what the view model starts with")
    func waitIsTwoSeconds() {
        #expect(RadioViewModel.settingsSyncPause == .seconds(2))
    }
}
