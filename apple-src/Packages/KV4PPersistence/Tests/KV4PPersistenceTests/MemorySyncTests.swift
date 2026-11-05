import CoreData
import Foundation
import SwiftData
import Testing

@testable import KV4PPersistence

/// What memories need to reach the other devices through CloudKit (ADR-0052). Two repositories on one store stand for
/// a device and what iCloud delivers to it.
@Suite("Memory sync")
struct MemorySyncTests {
    private static func storeURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).store")
    }

    /// Writes rows as they would arrive from another device.
    private static func arrive(_ url: URL, _ rows: [(ChannelMemory, position: Int, globalId: String)]) throws {
        let container = try ModelContainer(
            for: StoredMemory.self,
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        for row in rows {
            context.insert(StoredMemory(row.0, position: row.position, globalId: row.globalId))
        }
        try context.save()
    }

    private static func globalIds(_ url: URL) throws -> [String] {
        let container = try ModelContainer(
            for: StoredMemory.self,
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
        )
        return try ModelContext(container).fetch(FetchDescriptor<StoredMemory>()).map(\.globalId)
    }

    @Test("the model is one CloudKit can hold: nothing unique, every field with a default or optional")
    func schema() throws {
        let entity = try #require(Schema([StoredMemory.self]).entities.first)
        #expect(entity.uniquenessConstraints.isEmpty)
        for attribute in entity.attributes {
            #expect(!attribute.isUnique, "\(attribute.name)")
            #expect(attribute.isOptional || attribute.defaultValue != nil, "\(attribute.name)")
        }
    }

    @Test("a store can be opened without sync, for a user who turned it off")
    func withoutSync() async throws {
        let repository = try SwiftDataMemoryRepository(storeURL: Self.storeURL(), syncs: false)
        _ = try await repository.insert([ChannelMemory(name: "A", frequency: 146.52)])
        #expect(try await repository.all().map(\.name) == ["A"])
    }

    @Test("a change of another device is seen, also on memories already read")
    func seesChanges() async throws {
        let url = Self.storeURL()
        let device = try SwiftDataMemoryRepository(storeURL: url)
        let cloud = try SwiftDataMemoryRepository(storeURL: url)
        let memory = try #require(try await cloud.insert([ChannelMemory(name: "A", frequency: 146.52)]).first)
        #expect(try await device.all().map(\.name) == ["A"])
        var changed = memory
        changed.name = "B"
        try await cloud.update(changed)
        #expect(try await device.all().map(\.name) == ["B"])
        try await cloud.delete(id: memory.id)
        #expect(try await device.all().isEmpty)
    }

    @Test("a new order of another device is seen")
    func seesOrder() async throws {
        let url = Self.storeURL()
        let device = try SwiftDataMemoryRepository(storeURL: url)
        let cloud = try SwiftDataMemoryRepository(storeURL: url)
        let inserted = try await cloud.insert([
            ChannelMemory(name: "A", frequency: 146.52), ChannelMemory(name: "B", frequency: 146.54),
        ])
        #expect(try await device.all().map(\.name) == ["A", "B"])
        try await cloud.reorder(inserted.map(\.id).reversed())
        #expect(try await device.all().map(\.name) == ["B", "A"])
    }

    @Test("two memories with one number from two devices get a number each here")
    func sameNumber() async throws {
        let url = Self.storeURL()
        try Self.arrive(url, [
            (ChannelMemory(id: 1, name: "A", frequency: 146.52), position: 1, globalId: "a"),
            (ChannelMemory(id: 1, name: "B", frequency: 146.54), position: 2, globalId: "b"),
        ])
        let repository = try SwiftDataMemoryRepository(storeURL: url)
        let memories = try await repository.all()
        #expect(Set(memories.map(\.id)).count == 2)
        let second = try #require(memories.last)
        var changed = second
        changed.name = "C"
        try await repository.update(changed)
        #expect(try await repository.all().map(\.name) == ["A", "C"])
        try await repository.delete(id: second.id)
        #expect(try await repository.all().map(\.name) == ["A"])
    }

    @Test("a number stays while the app runs, also for a later memory after a delete")
    func stableNumbers() async throws {
        let repository = try SwiftDataMemoryRepository(storeURL: Self.storeURL())
        let inserted = try await repository.insert([
            ChannelMemory(name: "A", frequency: 146.52), ChannelMemory(name: "B", frequency: 146.54),
        ])
        let last = try #require(inserted.last)
        try await repository.delete(id: last.id)
        let new = try #require(try await repository.insert([ChannelMemory(name: "C", frequency: 146.56)]).first)
        #expect(new.id > last.id)
    }

    @Test("a memory with no number yet gets one")
    func noNumber() async throws {
        let url = Self.storeURL()
        try Self.arrive(url, [(ChannelMemory(id: 0, name: "A", frequency: 146.52), position: 1, globalId: "a")])
        let repository = try SwiftDataMemoryRepository(storeURL: url)
        #expect(try await repository.all().first?.id != 0)
    }

    @Test("the same memory from two devices becomes one, on both the same")
    func duplicates() async throws {
        let url = Self.storeURL()
        let memory = ChannelMemory(name: "A", frequency: 146.52, txTone: "67", group: "Local")
        try Self.arrive(url, [
            (memory, position: 1, globalId: "b"),
            (memory, position: 2, globalId: "a"),
        ])
        let repository = try SwiftDataMemoryRepository(storeURL: url)
        #expect(try await repository.all().map(\.name) == ["A"])
        #expect(try Self.globalIds(url) == ["a"])
    }

    @Test("memories that differ in any way both stay, as neither may get lost")
    func notDuplicates() async throws {
        let url = Self.storeURL()
        try Self.arrive(url, [
            (ChannelMemory(name: "A", frequency: 146.52, txTone: "67"), position: 1, globalId: "a"),
            (ChannelMemory(name: "A", frequency: 146.52, txTone: "71.9"), position: 2, globalId: "b"),
        ])
        let repository = try SwiftDataMemoryRepository(storeURL: url)
        #expect(try await repository.all().map(\.txTone) == ["67", "71.9"])
    }

    @Test("two memories on one place stand in the same order on every device")
    func samePosition() async throws {
        let url = Self.storeURL()
        try Self.arrive(url, [
            (ChannelMemory(id: 1, name: "Second", frequency: 146.52), position: 3, globalId: "b"),
            (ChannelMemory(id: 2, name: "First", frequency: 146.54), position: 3, globalId: "a"),
        ])
        let repository = try SwiftDataMemoryRepository(storeURL: url)
        #expect(try await repository.all().map(\.name) == ["First", "Second"])
    }

    @Test("a memory of an earlier version gets a global id, once, and keeps its number")
    func migration() async throws {
        let url = Self.storeURL()
        try Self.arrive(url, [(ChannelMemory(id: 7, name: "A", frequency: 146.52), position: 1, globalId: "")])
        let repository = try SwiftDataMemoryRepository(storeURL: url)
        #expect(try await repository.all().map(\.id) == [7])
        let first = try Self.globalIds(url)
        #expect(first.first?.isEmpty == false)
        let reopened = try SwiftDataMemoryRepository(storeURL: url)
        _ = try await reopened.all()
        #expect(try Self.globalIds(url) == first)
    }

    @Test("new memories have a global id of their own")
    func newGlobalIds() async throws {
        let url = Self.storeURL()
        let repository = try SwiftDataMemoryRepository(storeURL: url)
        _ = try await repository.insert([
            ChannelMemory(name: "A", frequency: 146.52), ChannelMemory(name: "B", frequency: 146.54),
        ])
        let ids = try Self.globalIds(url)
        #expect(Set(ids).count == 2)
        #expect(!ids.contains(""))
    }

    @Test("a change from iCloud is reported")
    func reportsChanges() async throws {
        let repository = try SwiftDataMemoryRepository(storeURL: Self.storeURL())
        let changes = repository.changes
        let reported = Task {
            for await _ in changes { return true }
            return false
        }
        // The stream listens from its first use on; repeat, as that moment is not visible from here.
        while !reported.isCancelled {
            NotificationCenter.default.post(name: .NSPersistentStoreRemoteChange, object: nil)
            try await Task.sleep(for: .milliseconds(5))
            if await Self.isDone(reported) { break }
        }
        #expect(await reported.value)
    }

    private static func isDone(_ task: Task<Bool, Never>) async -> Bool {
        await withTaskGroup(of: Bool?.self) { group in
            group.addTask { await task.value }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(5))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first != nil
        }
    }

    @Test("a repository without changes of its own reports none")
    func noChanges() async {
        struct Plain: MemoryRepository {
            func all() async throws -> [ChannelMemory] { [] }
            func insert(_ memories: [ChannelMemory]) async throws -> [ChannelMemory] { memories }
            func update(_ memory: ChannelMemory) async throws {}
            func delete(id: Int32) async throws {}
            func reorder(_ ids: [Int32]) async throws {}
            func renameGroup(_ group: String, to newName: String) async throws {}
        }
        for await _ in Plain().changes {
            Issue.record("no change expected")
        }
    }
}
