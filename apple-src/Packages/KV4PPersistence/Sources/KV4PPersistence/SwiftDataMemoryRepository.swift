import CoreData
import Foundation
import SwiftData

/// A stored memory. CloudKit holds no unique fields and needs a default for every field (ADR-0052).
@Model
final class StoredMemory {
    /// Identifies the memory on every device; empty in a store of an earlier version, until it is migrated.
    var globalId: String = ""
    /// A number of this device, which another device can use for another memory: the repository decides (ADR-0052).
    var memoryId: Int32 = 0
    var name: String = ""
    var frequency: Float = 0
    var offset: MemoryOffset = MemoryOffset.none
    var offsetKHz: Int = 600
    var txTone: String = "None"
    var rxTone: String = "None"
    var group: String = ""
    var skipDuringScan: Bool = false
    var accessToneHz: Int?
    var accessToneLengthMs: Int?
    /// A `MemoryKind`; empty in a store of an earlier version, until it is migrated (ADR-0065).
    var kind: String = ""
    var comment: String = ""
    var latitude: Double?
    var longitude: Double?
    /// The place in the stored order, from 1; 0 in a store of an earlier version, until it is migrated.
    var position: Int = 0

    init(_ memory: ChannelMemory, position: Int, globalId: String) {
        self.globalId = globalId
        self.position = position
        memoryId = memory.id
        update(from: memory)
    }

    func update(from memory: ChannelMemory) {
        name = memory.name
        frequency = memory.frequency
        offset = memory.offset
        offsetKHz = memory.offsetKHz
        txTone = memory.txTone
        rxTone = memory.rxTone
        group = memory.group
        skipDuringScan = memory.skipDuringScan
        accessToneHz = memory.accessToneHz
        accessToneLengthMs = memory.accessToneLengthMs
        kind = memory.kind.rawValue
        comment = memory.comment
        latitude = memory.latitude
        longitude = memory.longitude
    }

    /// The kind; for a memory of an earlier version, a repeater with an offset and a frequency without.
    private var memoryKind: MemoryKind { MemoryKind(rawValue: kind) ?? (offset == .none ? .frequency : .repeater) }

    /// Stores the kind of a memory of an earlier version, so that it stays as the offset changes.
    func migrateKind() {
        if kind != memoryKind.rawValue {
            kind = memoryKind.rawValue
        }
    }

    func memory(id: Int32) -> ChannelMemory {
        ChannelMemory(
            id: id,
            name: name,
            frequency: frequency,
            offset: offset,
            offsetKHz: offsetKHz,
            txTone: txTone,
            rxTone: rxTone,
            group: group,
            skipDuringScan: skipDuringScan,
            accessToneHz: accessToneHz,
            accessToneLengthMs: accessToneLengthMs,
            kind: memoryKind,
            comment: comment,
            latitude: latitude,
            longitude: longitude
        )
    }
}

/// `MemoryRepository` on SwiftData (ADR-0007), kept in sync through CloudKit where the app has the entitlement for it
/// (ADR-0052).
@ModelActor
public actor SwiftDataMemoryRepository: MemoryRepository {
    /// The numbers of this run, for the radio and the screens: a global id has its number while the app runs.
    private var numbers: [String: Int32] = [:]

    /// Stores at `storeURL`. With `syncs`, CloudKit takes part if the app is entitled to it; without, the store stays
    /// on this device.
    public init(storeURL: URL, syncs: Bool = true) throws {
        try self.init(configuration: ModelConfiguration(url: storeURL, cloudKitDatabase: syncs ? .automatic : .none))
    }

    /// Keeps the memories only while the repository exists (tests, previews).
    public static func inMemory() throws -> SwiftDataMemoryRepository {
        try SwiftDataMemoryRepository(configuration: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private init(configuration: ModelConfiguration) throws {
        self.init(modelContainer: try ModelContainer(for: StoredMemory.self, configurations: configuration))
    }

    /// iCloud has delivered changes.
    public nonisolated var changes: AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                for await _ in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange) {
                    continuation.yield()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public nonisolated var finishedSyncs: AsyncStream<MemorySync> { CloudKitSyncEvents.finishedSyncs }

    public func all() throws -> [ChannelMemory] {
        ChannelMemory.arranged(try ordered(in: newContext()).map(identified))
    }

    public func insert(_ memories: [ChannelMemory]) throws -> [ChannelMemory] {
        let context = newContext()
        var nextPosition = Self.nextPosition(after: try ordered(in: context))
        let inserted = memories.map { memory in
            let globalId = UUID().uuidString
            var memory = memory
            memory.id = assignNumber(to: globalId, preferred: 0)
            context.insert(StoredMemory(memory, position: nextPosition, globalId: globalId))
            nextPosition += 1
            return memory
        }
        try context.save()
        return inserted
    }

    public func update(_ memory: ChannelMemory) throws {
        let context = newContext()
        let existing = try ordered(in: context)
        if let stored = stored(memory.id, in: existing) {
            if stored.group != memory.group {
                stored.position = Self.nextPosition(after: existing)
            }
            stored.update(from: memory)
        }
        try context.save()
    }

    public func delete(id: Int32) throws {
        let context = newContext()
        if let stored = stored(id, in: try ordered(in: context)) {
            context.delete(stored)
        }
        try context.save()
    }

    public func reorder(_ ids: [Int32]) throws {
        let context = newContext()
        let existing = try ordered(in: context)
        let named = ids.compactMap { stored($0, in: existing) }
        let others = existing.filter { row in !named.contains { $0 === row } }
        place(named + others)
        try context.save()
    }

    public func renameGroup(_ group: String, to newName: String) throws {
        let context = newContext()
        for stored in try ordered(in: context) where stored.group == group {
            stored.group = newName
        }
        try context.save()
    }

    /// A context of its own for each step, so that it reads what iCloud has written since the last one.
    private func newContext() -> ModelContext {
        ModelContext(modelContainer)
    }

    /// The stored memories in their order, with everything a store of an earlier version or another device can lack:
    /// a global id, the order and no second copy of a memory. Each device does the same, so the result is the same.
    private func ordered(in context: ModelContext) throws -> [StoredMemory] {
        var stored = try context.fetch(
            FetchDescriptor<StoredMemory>(sortBy: [SortDescriptor(\.position), SortDescriptor(\.memoryId)])
        )
        for memory in stored {
            if memory.globalId.isEmpty {
                memory.globalId = UUID().uuidString
            }
            memory.migrateKind()
        }
        if stored.first?.position == 0 {
            // Groups alphabetically, no group last, and each group in the order the memories were added (ADR-0042).
            let key = { (memory: StoredMemory) in (memory.group.isEmpty ? 1 : 0, memory.group, memory.memoryId) }
            place(stored.sorted { key($0) < key($1) })
        }
        stored.sort { ($0.position, $0.globalId) < ($1.position, $1.globalId) }
        stored = withoutCopies(stored, in: context)
        for memory in stored {
            _ = number(of: memory)
        }
        if context.hasChanges {
            try context.save()
        }
        return stored
    }

    /// Two devices that had the same memories before they synced now hold each of them twice. Of memories alike in
    /// everything, the one with the lowest global id stays; those that differ in anything both stay, as none may get
    /// lost.
    private func withoutCopies(_ stored: [StoredMemory], in context: ModelContext) -> [StoredMemory] {
        var lowest: [ChannelMemory: String] = [:]
        for memory in stored {
            let content = memory.memory(id: 0)
            lowest[content] = min(lowest[content] ?? memory.globalId, memory.globalId)
        }
        return stored.filter { memory in
            guard lowest[memory.memory(id: 0)] != memory.globalId else { return true }
            context.delete(memory)
            return false
        }
    }

    private func identified(_ stored: StoredMemory) -> ChannelMemory {
        stored.memory(id: number(of: stored))
    }

    private func number(of memory: StoredMemory) -> Int32 {
        numbers[memory.globalId] ?? assignNumber(to: memory.globalId, preferred: memory.memoryId)
    }

    /// The number the memory had, if nothing else has it, so that it stays between launches; otherwise a new one.
    private func assignNumber(to globalId: String, preferred: Int32) -> Int32 {
        let isFree = preferred > 0 && !numbers.values.contains(preferred)
        let number = isFree ? preferred : (numbers.values.max() ?? 0) + 1
        numbers[globalId] = number
        return number
    }

    private func place(_ stored: [StoredMemory]) {
        for (index, memory) in stored.enumerated() {
            memory.position = index + 1
        }
    }

    private static func nextPosition(after stored: [StoredMemory]) -> Int {
        (stored.last?.position ?? 0) + 1
    }

    private func stored(_ id: Int32, in rows: [StoredMemory]) -> StoredMemory? {
        rows.first { numbers[$0.globalId] == id }
    }
}
