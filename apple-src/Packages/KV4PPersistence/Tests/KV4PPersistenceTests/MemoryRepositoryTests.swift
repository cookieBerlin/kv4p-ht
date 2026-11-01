import Foundation
import Testing

@testable import KV4PPersistence

/// Channel memories stored with SwiftData, like the Android `channel_memories` table.
@Suite("Memory repository")
struct MemoryRepositoryTests {
    static let repeater = ChannelMemory(
        name: "N0CALL • Example",
        frequency: 146.94,
        offset: .down,
        offsetKHz: 600,
        txTone: "100.0",
        rxTone: "None",
        group: "Local",
        skipDuringScan: false
    )
    static let simplex = ChannelMemory(name: "Simplex", frequency: 146.52)

    @Test("a new memory has Android's defaults")
    func defaults() {
        let memory = ChannelMemory(name: "A", frequency: 145)
        #expect(memory.id == 0)
        #expect(memory.offset == .none)
        #expect(memory.offsetKHz == 600)
        #expect(memory.txTone == "None")
        #expect(memory.rxTone == "None")
        #expect(memory.group == "")
        #expect(!memory.skipDuringScan)
        #expect(MemoryOffset.allCases.map(\.rawValue) == [0, 1, 2])
    }

    @Test("inserted memories get increasing ids and are listed in that order")
    func insert() async throws {
        let repository = try SwiftDataMemoryRepository.inMemory()
        let inserted = try await repository.insert([Self.repeater, Self.simplex])
        #expect(inserted.map(\.id) == [1, 2])
        #expect(try await repository.all() == inserted)
        let more = try await repository.insert([Self.simplex])
        #expect(more.map(\.id) == [3])
    }

    @Test("update and delete")
    func updateDelete() async throws {
        let repository = try SwiftDataMemoryRepository.inMemory()
        var memory = try #require(try await repository.insert([Self.repeater]).first)
        memory.name = "Renamed"
        memory.skipDuringScan = true
        try await repository.update(memory)
        #expect(try await repository.all() == [memory])
        var missing = memory
        missing.id = 99
        try await repository.update(missing)
        #expect(try await repository.all() == [memory])
        try await repository.delete(id: memory.id)
        try await repository.delete(id: 42)
        #expect(try await repository.all().isEmpty)
    }

    @Test("memories survive a restart of the app")
    func persists() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "kv4p-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let first = try SwiftDataMemoryRepository(storeURL: url)
        let inserted = try await first.insert([Self.repeater])
        let second = try SwiftDataMemoryRepository(storeURL: url)
        #expect(try await second.all() == inserted)
    }

    @Test("groups are the distinct non-empty group names, sorted")
    func groups() {
        var other = Self.simplex
        other.group = "Contest"
        #expect(ChannelMemory.groups(in: [Self.repeater, Self.simplex, other, Self.repeater]) == ["Contest", "Local"])
    }
}
