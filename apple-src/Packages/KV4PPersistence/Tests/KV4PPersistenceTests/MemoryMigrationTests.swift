import Foundation
import Testing

@testable import KV4PPersistence

/// A store written by an earlier version of the app gets an order (ADR-0042). `memories-before-position.store` comes
/// from that version: memories A to E with the groups Zulu, none, Alpha, Zulu and none.
@Suite("Memory migration")
struct MemoryMigrationTests {
    /// A copy of the earlier store that a test may change.
    static func earlierStore() throws -> URL {
        let fixture = try #require(
            Bundle.module.url(forResource: "memories-before-position", withExtension: "store", subdirectory: "Fixtures")
        )
        let url = FileManager.default.temporaryDirectory.appending(path: "kv4p-\(UUID().uuidString).store")
        try FileManager.default.copyItem(at: fixture, to: url)
        return url
    }

    @Test("groups become alphabetical, no group comes last, and a group keeps its memories in order")
    func migrates() async throws {
        let url = try Self.earlierStore()
        defer { try? FileManager.default.removeItem(at: url) }

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
        let url = try Self.earlierStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let repository = try SwiftDataMemoryRepository(storeURL: url)
        _ = try await repository.insert([ChannelMemory(name: "F", frequency: 145, group: "Alpha")])
        #expect(try await repository.all().map(\.name) == ["C", "F", "A", "D", "B", "E"])
    }

    @Test("memories of an earlier version follow the settings for the access tone")
    func accessTone() async throws {
        let url = try Self.earlierStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let repository = try SwiftDataMemoryRepository(storeURL: url)
        for memory in try await repository.all() {
            #expect(memory.accessToneHz == nil)
            #expect(memory.accessToneLengthMs == nil)
        }
    }
}
