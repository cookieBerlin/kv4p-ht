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

    init(_ memory: ChannelMemory) {
        memoryId = memory.id
        name = memory.name
        frequency = memory.frequency
        offset = memory.offset
        offsetKHz = memory.offsetKHz
        txTone = memory.txTone
        rxTone = memory.rxTone
        group = memory.group
        skipDuringScan = memory.skipDuringScan
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
            skipDuringScan: skipDuringScan
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
        try modelContext.fetch(FetchDescriptor<StoredMemory>(sortBy: [SortDescriptor(\.memoryId)])).map(\.memory)
    }

    public func insert(_ memories: [ChannelMemory]) throws -> [ChannelMemory] {
        var nextId = (try all().last?.id ?? 0) + 1
        let inserted = memories.map { memory in
            var memory = memory
            memory.id = nextId
            nextId += 1
            return memory
        }
        inserted.forEach { modelContext.insert(StoredMemory($0)) }
        try modelContext.save()
        return inserted
    }

    public func update(_ memory: ChannelMemory) throws {
        try stored(memory.id)?.update(from: memory)
        try modelContext.save()
    }

    public func delete(id: Int32) throws {
        if let stored = try stored(id) {
            modelContext.delete(stored)
        }
        try modelContext.save()
    }

    private func stored(_ id: Int32) throws -> StoredMemory? {
        try modelContext.fetch(FetchDescriptor<StoredMemory>(predicate: #Predicate { $0.memoryId == id })).first
    }
}
