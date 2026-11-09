import KV4PAPRS
import KV4PPersistence
import KV4PTestSupport
import Testing

@testable import KV4PRadio

/// What the app shows in its demo mode, for the accessibility audit (ADR-0062).
@MainActor
@Suite("Demo content")
struct DemoContentTests {
    @Test("the demo brings memories, packets of each kind and chats")
    func content() async throws {
        let model = RadioViewModel(
            makeController: { _, _ in RadioController(transport: ScriptedTransport()) },
            serialDevices: { [] },
            memories: try SwiftDataMemoryRepository.inMemory()
        )
        model.callsign = "N0CALL"
        await model.loadDemoContent()
        #expect(await KV4PTestSupport.eventually { model.memories.count == DemoContent.memories.count })
        #expect(Set(model.aprsEvents.map(\.kind)).isSuperset(of: [.message, .position, .object, .weather, .status]))
        #expect(model.conversations.map(\.peer) == ["N2CALL-7", "N1CALL"])
        #expect(model.newAPRSMessages > 0)
    }

    @Test("a second time adds nothing, so the demo stays as it is")
    func once() async throws {
        let model = RadioViewModel(
            makeController: { _, _ in RadioController(transport: ScriptedTransport()) },
            serialDevices: { [] },
            memories: try SwiftDataMemoryRepository.inMemory()
        )
        model.callsign = "N0CALL"
        await model.loadDemoContent()
        #expect(await KV4PTestSupport.eventually { model.memories.count == DemoContent.memories.count })
        await model.loadDemoContent()
        #expect(model.memories.count == DemoContent.memories.count)
    }
}
