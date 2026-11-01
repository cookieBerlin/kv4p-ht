import KV4PPersistence
import KV4PSimulator
import KV4PTestSupport
import Testing

@testable import KV4PProtocol
@testable import KV4PRadio

/// A repository whose storage fails.
struct FailingRepository: MemoryRepository {
    struct Failure: Error {}

    func all() async throws -> [ChannelMemory] { throw Failure() }
    func insert(_ memories: [ChannelMemory]) async throws -> [ChannelMemory] { throw Failure() }
    func update(_ memory: ChannelMemory) async throws { throw Failure() }
    func delete(id: Int32) async throws { throw Failure() }
}

/// Memories, groups, scan and the RepeaterBook import of the radio screen.
@MainActor
@Suite("Radio view model memories")
struct RadioViewModelMemoryTests {
    static let local = ChannelMemory(name: "N0CALL • Example", frequency: 146.94, offset: .down, group: "Local")
    static let simplex = ChannelMemory(name: "Simplex", frequency: 146.52)
    static let csv = """
        Freq,Input,Offset,Tone,Location,State,County,Call,Use,Miles,Bearing,Degrees
        147.12000,147.72000,+0.6,100.0,Sample Town,XX,Sample,N1CALL,OPEN,5.0,E,90
        """

    static func model(_ repository: SwiftDataMemoryRepository) -> RadioViewModel {
        RadioViewModel(
            makeController: { _, rxAudio in
                let clock = ManualClock()
                let transport = SimulatorTransport(simulator: RadioSimulator(scenario: .ble), clock: clock)
                return RadioController(transport: transport, clock: clock, rxAudio: rxAudio)
            },
            serialDevices: { [] },
            memories: repository
        )
    }

    func connected(_ repository: SwiftDataMemoryRepository) async -> RadioViewModel {
        let model = Self.model(repository)
        await model.connect()
        #expect(await RadioViewModelTests.eventually(model) { $0.isReady && $0.snapshot.isInSync })
        return model
    }

    @Test("memories load, filter by group and are saved, edited and deleted")
    func crud() async throws {
        let repository = try SwiftDataMemoryRepository.inMemory()
        _ = try await repository.insert([Self.local])
        let model = Self.model(repository)
        await model.loadMemories()
        #expect(model.memories.map(\.name) == [Self.local.name])
        await model.save(Self.simplex)
        #expect(model.memories.map(\.name) == [Self.local.name, "Simplex"])
        #expect(model.groups == ["Local"])
        model.selectedGroup = "Local"
        #expect(model.visibleMemories.map(\.name) == [Self.local.name])
        model.selectedGroup = nil
        var edited = try #require(model.memories.last)
        edited.name = "Calling"
        await model.save(edited)
        #expect(model.memories.map(\.name) == [Self.local.name, "Calling"])
        await model.delete(edited)
        #expect(model.memories.map(\.name) == [Self.local.name])
    }

    @Test("selecting a memory tunes the radio and marks it active")
    func tune() async throws {
        let repository = try SwiftDataMemoryRepository.inMemory()
        let model = await connected(repository)
        await model.save(Self.local)
        let memory = try #require(model.memories.first)
        #expect(model.activeMemoryId == nil)
        await model.tune(to: memory)
        #expect(
            await RadioViewModelTests.eventually(model) {
                $0.snapshot.isInSync && $0.snapshot.deviceState?.radio.freqTx == 146.34
            }
        )
        #expect(model.activeMemoryId == memory.id)
        #expect(model.frequencyText == "146.9400")
    }

    @Test("scan runs over the visible memories and stops again")
    func scan() async throws {
        let repository = try SwiftDataMemoryRepository.inMemory()
        let model = await connected(repository)
        await model.save(Self.local)
        await model.save(Self.simplex)
        model.selectedGroup = "Local"
        await model.toggleScan()
        #expect(model.isScanning)
        #expect(await RadioViewModelTests.eventually(model) { $0.activeMemoryId == model.memories.first?.id })
        await model.toggleScan()
        #expect(!model.isScanning)
    }

    @Test("a RepeaterBook export becomes a group of memories")
    func importCSV() async throws {
        let repository = try SwiftDataMemoryRepository.inMemory()
        let model = await connected(repository)
        await model.importRepeaterBook(Self.csv, group: "Trip")
        #expect(model.memories.map(\.name) == ["N1CALL • Sample Town"])
        #expect(model.groups == ["Trip"])
        #expect(model.message == "Imported 1 repeater.")
        await model.importRepeaterBook("Name\nA", group: "")
        #expect(model.message == "This file is not a RepeaterBook CSV export.")
    }

    @Test("importing needs the radio's frequency range")
    func importNeedsRadio() async throws {
        let model = Self.model(try SwiftDataMemoryRepository.inMemory())
        await model.importRepeaterBook(Self.csv, group: "")
        #expect(model.message == "Connect the radio first, so that only repeaters it can receive are imported.")
        #expect(model.memories.isEmpty)
    }

    @Test("without a repository there are no memories")
    func noRepository() async {
        let model = RadioViewModelTests.model()
        await model.loadMemories()
        await model.save(Self.simplex)
        await model.delete(Self.simplex)
        await model.toggleScan()
        await model.tune(to: Self.simplex)
        #expect(model.memories.isEmpty)
        #expect(!model.isScanning)
    }

    @Test("storage failures are reported")
    func storageFails() async {
        let model = RadioViewModel(makeController: { _, _ in RadioController(transport: ScriptedTransport()) }, serialDevices: { [] }, memories: FailingRepository())
        await model.loadMemories()
        #expect(model.message == "The memories could not be loaded or saved.")
        await model.save(Self.simplex)
        await model.delete(Self.simplex)
        #expect(model.message == "The memories could not be loaded or saved.")
    }
}
