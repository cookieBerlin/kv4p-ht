import Foundation
import Testing

@testable import KV4PPersistence

/// What a memory is, a comment and a position (ADR-0065).
@Suite("Memory kind, comment and position")
struct MemoryKindTests {
    static let beacon = ChannelMemory(
        name: "N0CALL",
        frequency: 144.48,
        kind: .beacon,
        comment: "Example beacon",
        latitude: 12.5,
        longitude: -45.25
    )

    @Test("a new memory is a frequency, without a comment or a position")
    func defaults() {
        let memory = ChannelMemory(name: "A", frequency: 145)
        #expect(memory.kind == .frequency)
        #expect(memory.comment == "")
        #expect(memory.latitude == nil)
        #expect(memory.longitude == nil)
        #expect(MemoryKind.allCases.map(\.rawValue) == ["frequency", "repeater", "beacon"])
    }

    @Test("kind, comment and position are stored and updated")
    func stored() async throws {
        let repository = try SwiftDataMemoryRepository.inMemory()
        var memory = try #require(try await repository.insert([Self.beacon]).first)
        #expect(try await repository.all() == [memory])
        memory.kind = .repeater
        memory.comment = ""
        memory.latitude = nil
        memory.longitude = 1
        try await repository.update(memory)
        #expect(try await repository.all() == [memory])
    }

    @Test("a memory of an earlier version becomes a repeater with an offset and a frequency without, and stays one")
    func migrates() async throws {
        let url = MemorySyncTests.storeURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let repeater = ChannelMemory(name: "R", frequency: 145.6, offset: .down, kind: .beacon)
        let simplex = ChannelMemory(name: "S", frequency: 145.5, kind: .beacon)
        try MemorySyncTests.arrive(url, [(repeater, 1, "a"), (simplex, 2, "b")]) { $0.kind = "" }

        let repository = try SwiftDataMemoryRepository(storeURL: url, syncs: false)
        #expect(try await repository.all().map(\.kind) == [.repeater, .frequency])
        // Stored, so that it syncs as it is and stays when the offset changes.
        var memory = try #require(try await repository.all().first)
        memory.offset = .none
        try await repository.update(memory)
        #expect(try await repository.all().map(\.kind) == [.repeater, .frequency])
    }

    @Test("the memories of the earliest stored version are frequencies")
    func earliest() async throws {
        let url = try MemoryMigrationTests.earlierStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let repository = try SwiftDataMemoryRepository(storeURL: url)
        for memory in try await repository.all() {
            #expect(memory.kind == (memory.offset == .none ? .frequency : .repeater))
            #expect(memory.comment == "")
            #expect(memory.latitude == nil && memory.longitude == nil)
        }
    }
}
