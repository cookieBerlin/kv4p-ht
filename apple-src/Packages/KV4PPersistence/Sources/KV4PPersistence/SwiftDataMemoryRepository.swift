import Foundation
import SwiftData

@Model
final class StoredMemory {
    @Attribute(.unique) var memoryId: Int32
    var name: String
    var frequency: Float
    var offset: MemoryOffset
    var offsetKHz: Int
    var txTone: String
    var rxTone: String
    var group: String
    var skipDuringScan: Bool
    var accessToneHz: Int?
    var accessToneLengthMs: Int?
    /// The place in the stored order, from 1; 0 in a store of an earlier version, until it is migrated.
    var position: Int = 0

    init(_ memory: ChannelMemory, position: Int) {
        self.position = position
        memoryId = memory.id
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
    }

    var memory: ChannelMemory {
        ChannelMemory(
            id: memoryId,
            name: name,
            frequency: frequency,
            offset: offset,
            offsetKHz: offsetKHz,
            txTone: txTone,
            rxTone: rxTone,
            group: group,
            skipDuringScan: skipDuringScan,
            accessToneHz: accessToneHz,
            accessToneLengthMs: accessToneLengthMs
        )
    }
}

/// `MemoryRepository` on SwiftData (ADR-0007).
@ModelActor
public actor SwiftDataMemoryRepository: MemoryRepository {
    /// Stores at `storeURL`.
    public init(storeURL: URL) throws {
        try self.init(configuration: ModelConfiguration(url: storeURL))
    }

    /// Keeps the memories only while the repository exists (tests, previews).
    public static func inMemory() throws -> SwiftDataMemoryRepository {
        try SwiftDataMemoryRepository(configuration: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private init(configuration: ModelConfiguration) throws {
        self.init(modelContainer: try ModelContainer(for: StoredMemory.self, configurations: configuration))
    }

    public func all() throws -> [ChannelMemory] {
        ChannelMemory.arranged(try ordered().map(\.memory))
    }

    public func insert(_ memories: [ChannelMemory]) throws -> [ChannelMemory] {
        let existing = try ordered()
        var nextId = (existing.map(\.memoryId).max() ?? 0) + 1
        var nextPosition = Self.nextPosition(after: existing)
        let inserted = memories.map { memory in
            var memory = memory
            memory.id = nextId
            nextId += 1
            return memory
        }
        for memory in inserted {
            modelContext.insert(StoredMemory(memory, position: nextPosition))
            nextPosition += 1
        }
        try modelContext.save()
        return inserted
    }

    public func update(_ memory: ChannelMemory) throws {
        let existing = try ordered()
        if let stored = existing.first(where: { $0.memoryId == memory.id }) {
            if stored.group != memory.group {
                stored.position = Self.nextPosition(after: existing)
            }
            stored.update(from: memory)
        }
        try modelContext.save()
    }

    public func delete(id: Int32) throws {
        if let stored = try stored(id) {
            modelContext.delete(stored)
        }
        try modelContext.save()
    }

    public func reorder(_ ids: [Int32]) throws {
        let existing = try ordered()
        let named = ids.compactMap { id in existing.first { $0.memoryId == id } }
        let others = existing.filter { !ids.contains($0.memoryId) }
        place(named + others)
        try modelContext.save()
    }

    public func renameGroup(_ group: String, to newName: String) throws {
        for stored in try ordered() where stored.group == group {
            stored.group = newName
        }
        try modelContext.save()
    }

    /// The stored memories in their order. A store of an earlier version gets its order here: groups alphabetically,
    /// no group last, and each group in the order the memories were added (ADR-0042).
    private func ordered() throws -> [StoredMemory] {
        let stored = try modelContext.fetch(
            FetchDescriptor<StoredMemory>(sortBy: [SortDescriptor(\.position), SortDescriptor(\.memoryId)])
        )
        guard stored.first?.position == 0 else { return stored }
        let migrated = stored.sorted {
            ($0.group.isEmpty ? 1 : 0, $0.group, $0.memoryId) < ($1.group.isEmpty ? 1 : 0, $1.group, $1.memoryId)
        }
        place(migrated)
        try modelContext.save()
        return migrated
    }

    private func place(_ stored: [StoredMemory]) {
        for (index, memory) in stored.enumerated() {
            memory.position = index + 1
        }
    }

    private static func nextPosition(after stored: [StoredMemory]) -> Int {
        (stored.last?.position ?? 0) + 1
    }

    private func stored(_ id: Int32) throws -> StoredMemory? {
        try modelContext.fetch(FetchDescriptor<StoredMemory>(predicate: #Predicate { $0.memoryId == id })).first
    }
}
