import Foundation
import KV4PPersistence
import KV4PTestSupport
import Testing

@testable import KV4PRadio

/// What the memory editor in the settings asks of the model (ADR-0042).
@MainActor
@Suite("Radio view model: memory editor")
struct RadioViewModelMemoryEditorTests {
    static func memory(_ name: String, group: String = "") -> ChannelMemory {
        ChannelMemory(name: name, frequency: 146.52, group: group)
    }

    static func model() async throws -> RadioViewModel {
        let repository = try SwiftDataMemoryRepository.inMemory()
        _ = try await repository.insert([
            memory("A", group: "One"), memory("B", group: "One"), memory("C", group: "Two"), memory("D"),
        ])
        let model = RadioViewModelMemoryTests.model(repository)
        await model.loadMemories()
        return model
    }

    static func names(_ model: RadioViewModel) -> [String] {
        model.memories.map(\.name)
    }

    @Test("the blocks hold every memory, also those without a group")
    func blocks() async throws {
        let model = try await Self.model()
        #expect(model.memoryBlocks.map(\.name) == ["One", "Two", ""])
        #expect(model.groups == ["One", "Two"])
    }

    @Test("groups and the memories in a group can be moved")
    func moves() async throws {
        let model = try await Self.model()
        await model.moveGroups(IndexSet(integer: 2), to: 0)
        #expect(Self.names(model) == ["D", "A", "B", "C"])
        await model.moveMemories(inGroup: "One", IndexSet(integer: 1), to: 0)
        #expect(Self.names(model) == ["D", "B", "A", "C"])
    }

    @Test("selected memories move to the end of another group")
    func moveToGroup() async throws {
        let model = try await Self.model()
        await model.move(Array(model.memories[0...1]), toGroup: "Two")
        #expect(Self.names(model) == ["C", "A", "B", "D"])
        #expect(model.groups == ["Two"])
    }

    @Test("several memories can be deleted at once")
    func deleteSeveral() async throws {
        let model = try await Self.model()
        await model.delete(Array(model.memories[1...2]))
        #expect(Self.names(model) == ["A", "D"])
    }

    @Test("a group can be renamed; the group shown follows, and a blank name changes nothing")
    func rename() async throws {
        let model = try await Self.model()
        model.selectedGroup = "One"
        await model.renameGroup("One", to: "  First ")
        #expect(model.groups == ["First", "Two"])
        #expect(model.selectedGroup == "First")
        await model.renameGroup("Two", to: "Second")
        #expect(model.selectedGroup == "First")
        await model.renameGroup("First", to: "  ")
        #expect(model.groups == ["First", "Second"])
    }

    @Test("deleting a group removes its memories or keeps them without a group")
    func deleteGroup() async throws {
        let model = try await Self.model()
        await model.deleteGroup("Two", keepingMemories: true)
        #expect(Self.names(model) == ["A", "B", "D", "C"])
        #expect(model.groups == ["One"])
        await model.deleteGroup("One", keepingMemories: false)
        #expect(Self.names(model) == ["D", "C"])
    }

    @Test("the group shown falls back to all when it no longer exists")
    func selectedGroupGone() async throws {
        let model = try await Self.model()
        model.selectedGroup = "Two"
        await model.delete(try #require(model.memories.first { $0.group == "Two" }))
        #expect(model.selectedGroup == nil)
        model.selectedGroup = "One"
        await model.deleteGroup("One", keepingMemories: false)
        #expect(model.selectedGroup == nil)
    }

    @Test("storage failures are reported")
    func storageFails() async {
        let model = RadioViewModel(
            makeController: { _, _ in RadioController(transport: ScriptedTransport()) },
            serialDevices: { [] },
            memories: FailingRepository()
        )
        await model.moveGroups(IndexSet(integer: 0), to: 0)
        #expect(model.message == "The memories could not be loaded or saved.")
    }

    // MARK: Form

    @Test(
        "the form says what keeps a memory from being saved",
        arguments: [
            (ChannelMemory(name: " ", frequency: 146.52), "Enter a name."),
            (ChannelMemory(name: "A", frequency: 0), "Enter a frequency in MHz."),
            (ChannelMemory(name: "A", frequency: .nan), "Enter a frequency in MHz."),
            (ChannelMemory(name: "A", frequency: 900), "Enter a frequency in MHz."),
            (ChannelMemory(name: "A", frequency: 146.52, offset: .up, offsetKHz: -1), "Enter the offset in kHz."),
            (ChannelMemory(name: "A", frequency: 146.52, offset: .none, offsetKHz: -1), nil),
            (ChannelMemory(name: "A", frequency: 146.52), nil),
        ] as [(ChannelMemory, String?)]
    )
    func problems(memory: ChannelMemory, expected: String?) {
        #expect(RadioViewModelTests.model().memoryProblem(memory) == expected)
    }

    @Test("with a radio, the frequency must lie in its range")
    func problemInRange() async {
        let model = RadioViewModelTests.model()
        await model.connect()
        #expect(await RadioViewModelTests.eventually(model) { $0.isReady })
        let far = ChannelMemory(name: "A", frequency: 435)
        #expect(model.memoryProblem(far) == "This radio receives from 134.0000 to 174.0000 MHz.")
        #expect(model.memoryProblem(ChannelMemory(name: "A", frequency: 146.52)) == nil)
    }

    @Test("the form shows where a repeater memory transmits")
    func transmitText() {
        let model = RadioViewModelTests.model()
        #expect(model.transmitText(for: ChannelMemory(name: "A", frequency: 146.52)) == nil)
        let down = ChannelMemory(name: "A", frequency: 439.1, offset: .down, offsetKHz: 7600)
        #expect(model.transmitText(for: down) == "Transmits on 431.5000 MHz")
        let up = ChannelMemory(name: "A", frequency: 145, offset: .up, offsetKHz: 600)
        #expect(model.transmitText(for: up) == "Transmits on 145.6000 MHz")
    }

    // MARK: Import

    static let csv = """
        Freq,Input,Offset,Tone,Location,State,County,Call,Use,Miles,Bearing,Degrees
        147.12000,147.72000,+0.6,100.0,Sample Town,XX,Sample,N1CALL,OPEN,5.0,E,90
        147.12000,147.72000,+0.6,100.0,Sample Town,XX,Sample,N1CALL,OPEN,5.0,E,90
        146.94000,146.34000,-0.6,100.0,Other Town,XX,Sample,N2CALL,OPEN,5.0,E,90
        440.10000,445.10000,+5,100.0,Far Town,XX,Sample,N3CALL,OPEN,5.0,E,90
        """

    @Test("the preview counts what is imported and what is left out for the chosen group")
    func preview() async throws {
        let repository = try SwiftDataMemoryRepository.inMemory()
        _ = try await repository.insert([ChannelMemory(name: "N2CALL • Other Town", frequency: 146.94, group: "Trip")])
        let model = RadioViewModelMemoryTests.model(repository)
        await model.loadMemories()
        #expect(model.importPreview(Self.csv, group: "Trip") == nil)  // no radio yet
        #expect(!model.canImportRepeaters)
        await model.connect()
        #expect(await RadioViewModelTests.eventually(model) { $0.isReady })
        #expect(model.canImportRepeaters)

        let inTrip = try #require(model.importPreview(Self.csv, group: "Trip"))
        #expect(inTrip.memories.map(\.name) == ["N1CALL • Sample Town"])
        #expect(inTrip.outOfRange == 1)
        #expect(inTrip.duplicates == 2)
        #expect(
            inTrip.summary == "1 repeater to import. Left out: 1 outside the radio's range, 2 already in this group."
        )

        let elsewhere = try #require(model.importPreview(Self.csv, group: "Other"))
        #expect(elsewhere.memories.count == 2)
        #expect(elsewhere.duplicates == 1)
        #expect(
            elsewhere.summary
                == "2 repeaters to import. Left out: 1 outside the radio's range, 1 already in this group."
        )

        #expect(model.importPreview("Name\nA", group: "") == nil)
    }

    @Test("a plain file has nothing left out")
    func previewPlain() {
        let preview = RepeaterBookPreview(memories: [], outOfRange: 0, duplicates: 0)
        #expect(preview.summary == "0 repeaters to import.")
    }

    @Test("importing skips what is already in the group")
    func importSkips() async throws {
        let repository = try SwiftDataMemoryRepository.inMemory()
        let model = RadioViewModelMemoryTests.model(repository)
        await model.loadMemories()
        await model.connect()
        #expect(await RadioViewModelTests.eventually(model) { $0.isReady })
        await model.importRepeaterBook(Self.csv, group: "Trip")
        #expect(model.memories.count == 2)
        #expect(model.message == "Imported 2 repeaters.")
        await model.importRepeaterBook(Self.csv, group: "Trip")
        #expect(model.memories.count == 2)
        #expect(model.message == "Imported 0 repeaters.")
    }
}
