import Foundation
import SwiftData
import Testing

@testable import KV4PPersistence

/// The stored memory as it was before it had a position.
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

    init(id: Int32, name: String, group: String) {
        memoryId = id
        self.name = name
        frequency = 145
        offset = .none
        offsetKHz = 600
        txTone = "None"
        rxTone = "None"
        self.group = group
        skipDuringScan = false
    }
}

/// A store written by an earlier version of the app gets an order (ADR-0042).
@Suite("Memory migration")
struct MemoryMigrationTests {
    static func earlierStore(at url: URL) throws {
        let container = try ModelContainer(for: StoredMemory.self, configurations: ModelConfiguration(url: url))
        let context = ModelContext(container)
        for (id, name, group) in [
            (1, "A", "Zulu"), (2, "B", ""), (3, "C", "Alpha"), (4, "D", "Zulu"), (5, "E", ""),
        ] as [(Int32, String, String)] {
            context.insert(StoredMemory(id: id, name: name, group: group))
        }
        try context.save()
    }

    @Test("groups become alphabetical, no group comes last, and a group keeps its memories in order")
    func migrates() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "kv4p-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        try Self.earlierStore(at: url)

        let repository = try SwiftDataMemoryRepository(storeURL: url)
        #expect(try await repository.all().map(\.name) == ["C", "A", "D", "B", "E"])
        #expect(try await repository.all().map(\.id) == [3, 1, 4, 2, 5])

        // The order is stored, so that it stays after a reorder and a new start.
        try await repository.reorder([2, 5, 3, 1, 4])
        let inserted = try await repository.insert([ChannelMemory(name: "F", frequency: 145)])
        #expect(inserted.map(\.id) == [6])
        let restarted = try SwiftDataMemoryRepository(storeURL: url)
        #expect(try await restarted.all().map(\.name) == ["B", "E", "F", "C", "A", "D"])
    }

    @Test("a memory added right after the update is placed behind the migrated ones")
    func insertFirst() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "kv4p-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        try Self.earlierStore(at: url)

        let repository = try SwiftDataMemoryRepository(storeURL: url)
        _ = try await repository.insert([ChannelMemory(name: "F", frequency: 145, group: "Alpha")])
        #expect(try await repository.all().map(\.name) == ["C", "F", "A", "D", "B", "E"])
    }
}
