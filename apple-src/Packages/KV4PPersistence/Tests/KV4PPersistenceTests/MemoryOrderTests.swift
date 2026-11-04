import Foundation
import Testing

@testable import KV4PPersistence

/// The stored order of the memories and their groups (ADR-0042).
@Suite("Memory order")
struct MemoryOrderTests {
    static func memory(_ name: String, group: String = "", id: Int32 = 0) -> ChannelMemory {
        ChannelMemory(id: id, name: name, frequency: 145, group: group)
    }

    static func names(_ repository: SwiftDataMemoryRepository) async throws -> [String] {
        try await repository.all().map(\.name)
    }

    @Test("groups keep the order of their first memory and leave out no group")
    func groups() {
        let memories = [Self.memory("A", group: "Local"), Self.memory("B"), Self.memory("C", group: "Contest")]
        #expect(ChannelMemory.groups(in: memories + memories) == ["Local", "Contest"])
    }

    @Test("the memories of a group stay together, also without a group")
    func blocks() {
        let memories = [
            Self.memory("A", group: "Local"), Self.memory("B"), Self.memory("C", group: "Local"), Self.memory("D"),
        ]
        #expect(ChannelMemory.arranged(memories).map(\.name) == ["A", "C", "B", "D"])
        let blocks = ChannelMemory.blocks(in: memories)
        #expect(blocks.map(\.name) == ["Local", ""])
        #expect(blocks.map(\.id) == ["Local", ""])
        #expect(blocks.map { $0.memories.map(\.name) } == [["A", "C"], ["B", "D"]])
    }

    static let blocks = ChannelMemory.blocks(in: [
        memory("A", group: "One", id: 1), memory("B", group: "One", id: 2), memory("C", group: "One", id: 3),
        memory("D", group: "Two", id: 4), memory("E", group: "Three", id: 5),
    ])

    @Test(
        "moving groups gives the new order of all memories",
        arguments: [
            (IndexSet(integer: 2), 0, [5, 1, 2, 3, 4]),
            (IndexSet(integer: 0), 3, [4, 5, 1, 2, 3]),
            (IndexSet(integer: 0), 2, [4, 1, 2, 3, 5]),
            (IndexSet([0, 1]), 3, [5, 1, 2, 3, 4]),
        ] as [(IndexSet, Int, [Int32])]
    )
    func moveGroups(offsets: IndexSet, destination: Int, expected: [Int32]) {
        #expect(ChannelMemory.order(ofBlocks: Self.blocks, movingGroups: offsets, to: destination) == expected)
    }

    @Test("moving memories stays inside their group")
    func moveMemories() {
        let moved = ChannelMemory.order(ofBlocks: Self.blocks, inGroup: "One", moving: IndexSet(integer: 2), to: 0)
        #expect(moved == [3, 1, 2, 4, 5])
        let other = ChannelMemory.order(ofBlocks: Self.blocks, inGroup: "Two", moving: IndexSet(integer: 0), to: 1)
        #expect(other == [1, 2, 3, 4, 5])
    }

    @Test("reordering is stored, and memories not named follow in their order")
    func reorder() async throws {
        let repository = try SwiftDataMemoryRepository.inMemory()
        _ = try await repository.insert([Self.memory("A"), Self.memory("B"), Self.memory("C")])
        try await repository.reorder([3, 1, 99])
        #expect(try await Self.names(repository) == ["C", "A", "B"])
        #expect(try await repository.all().map(\.id) == [3, 1, 2])
    }

    @Test("a new memory goes to the end of its group and gets an unused id after reordering")
    func insertAfterReorder() async throws {
        let repository = try SwiftDataMemoryRepository.inMemory()
        _ = try await repository.insert([
            Self.memory("A", group: "One"), Self.memory("B", group: "Two"), Self.memory("C", group: "One"),
        ])
        try await repository.reorder([3, 1, 2])
        let inserted = try await repository.insert([Self.memory("D", group: "One")])
        #expect(inserted.map(\.id) == [4])
        #expect(try await Self.names(repository) == ["C", "A", "D", "B"])
    }

    @Test("a memory moved to another group goes to its end; other changes keep its place")
    func updateGroup() async throws {
        let repository = try SwiftDataMemoryRepository.inMemory()
        var inserted = try await repository.insert([
            Self.memory("A", group: "One"), Self.memory("B", group: "One"), Self.memory("C", group: "Two"),
            Self.memory("D", group: "Two"),
        ])
        inserted[0].name = "Renamed"
        try await repository.update(inserted[0])
        #expect(try await Self.names(repository) == ["Renamed", "B", "C", "D"])
        inserted[0].group = "Two"
        try await repository.update(inserted[0])
        #expect(try await Self.names(repository) == ["B", "C", "D", "Renamed"])
    }

    @Test("renaming a group keeps its place, and a name in use joins the two groups")
    func rename() async throws {
        let repository = try SwiftDataMemoryRepository.inMemory()
        _ = try await repository.insert([
            Self.memory("A", group: "One"), Self.memory("B", group: "Two"), Self.memory("C", group: "Three"),
        ])
        try await repository.renameGroup("One", to: "First")
        #expect(try await repository.all().map(\.group) == ["First", "Two", "Three"])
        try await repository.renameGroup("Three", to: "First")
        #expect(try await repository.all().map(\.name) == ["A", "C", "B"])
        #expect(try await repository.all().map(\.group) == ["First", "First", "Two"])
    }
}
