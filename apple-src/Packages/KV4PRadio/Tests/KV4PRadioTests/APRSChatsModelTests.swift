import KV4PAPRS
import KV4PPersistence
import KV4PTestSupport
import Testing

@testable import KV4PRadio

/// Chats in the view model: from memory and the store, read state and their own time to stay (ADR-0061).
@MainActor
@Suite("APRS chats in the view model")
struct APRSChatsModelTests {
    private static let day: Int64 = 86_400_000

    @MainActor
    private final class Setup {
        let link = FakeLink()
        let time = TestTime()
        let settings: MemorySettingsStore
        let history: any APRSHistoryStoring
        let model: RadioViewModel

        init(history: (any APRSHistoryStoring)? = nil, settings: AppSettings = AppSettings(), listLimit: Int = 500)
            throws
        {
            self.history = try history ?? SwiftDataAPRSHistory.inMemory()
            self.settings = MemorySettingsStore(settings)
            let time = time
            model = RadioViewModel(
                makeController: { _, _ in RadioController(transport: ScriptedTransport()) },
                serialDevices: { [] },
                internet: link,
                aprsHistory: self.history,
                settings: self.settings,
                now: { time.ms },
                aprsListLimit: listLimit
            )
            model.callsign = "N0CALL"
        }

        func receive(_ line: String, after ms: Int64 = 1_000) async {
            let before = model.aprsEvents.map(\.lastSeenMs)
            time.advance(by: ms)
            link.receive.yield(line)
            #expect(await KV4PTestSupport.eventually { self.model.aprsEvents.map(\.lastSeenMs) != before })
        }
    }

    @Test("chats show the messages to and from this station, also those no longer in memory")
    func fromStore() async throws {
        let setup = try Setup(listLimit: 1)
        await setup.receive("N1CALL>APRS,TCPIP*::N0CALL   :One")
        await setup.receive("N2CALL>APRS,TCPIP*::N0CALL   :Two")
        await setup.receive("N3CALL>APRS,TCPIP*:>Status")
        #expect(await KV4PTestSupport.eventually { setup.model.conversations.map(\.peer) == ["N2CALL", "N1CALL"] })
        #expect(setup.model.messages(with: "N1CALL").map(\.body) == ["One"])
        #expect(await KV4PTestSupport.eventually { setup.model.storedPacketCount == 2 })

        let restarted = try Setup(history: setup.history, listLimit: 1)
        #expect(await KV4PTestSupport.eventually { restarted.model.conversations.count == 2 })
        #expect(restarted.model.newAPRSMessages == 2)
    }

    @Test("what was read stays read after a restart, on this device")
    func readState() async throws {
        let setup = try Setup()
        await setup.receive("N1CALL>APRS,TCPIP*::N0CALL   :One")
        setup.model.isAPRSVisible = true
        setup.model.openChat = "N1CALL"
        #expect(setup.model.newAPRSMessages == 0)
        #expect(setup.settings.settings.chatReadUntilMs["N1CALL"] == setup.time.ms)
        #expect(!SettingsSync.values(of: AppSettings()).keys.contains("chatReadUntilMs"))
        #expect(await KV4PTestSupport.eventually { setup.model.storedPacketCount == 1 })
        let restarted = try Setup(history: setup.history, settings: setup.settings.settings)
        #expect(await KV4PTestSupport.eventually { restarted.model.conversations.count == 1 })
        #expect(restarted.model.newAPRSMessages == 0)
    }

    @Test("a chat that is open but not on screen marks nothing as read")
    func notOnScreen() async throws {
        let setup = try Setup()
        await setup.receive("N1CALL>APRS,TCPIP*::N0CALL   :One")
        setup.model.openChat = "N1CALL"
        #expect(setup.model.newAPRSMessages == 1)
    }

    @Test("a tap on a message of a chat opens it on the chats page; any other message fills in the recipient")
    func opensChat() async throws {
        let setup = try Setup()
        await setup.receive("N1CALL>APRS,TCPIP*::N0CALL   :Mine")
        await setup.receive("N2CALL>APRS,TCPIP*::N3CALL   :Theirs")
        let mine = try #require(setup.model.aprsEvents.first { $0.fromCallsign == "N1CALL" })
        let theirs = try #require(setup.model.aprsEvents.first { $0.fromCallsign == "N2CALL" })
        setup.model.open(mine)
        #expect(setup.model.aprsPage == .chats)
        #expect(setup.model.openChat == "N1CALL")
        #expect(setup.model.aprsRecipient == "N1CALL")
        #expect(setup.settings.settings.aprsPage == .chats)
        setup.model.aprsPage = .packets
        setup.model.open(theirs)
        #expect(setup.model.aprsPage == .packets)
        #expect(setup.model.aprsRecipient == "N2CALL")
        #expect(setup.model.chatPeer(of: mine) == "N1CALL")
        #expect(setup.model.chatPeer(of: theirs) == nil)
    }

    @Test("deleting a message or all of them takes them from the chats too")
    func deletes() async throws {
        let setup = try Setup()
        await setup.receive("N1CALL>APRS,TCPIP*::N0CALL   :One")
        await setup.receive("N2CALL>APRS,TCPIP*::N0CALL   :Two")
        let one = try #require(setup.model.aprsEvents.first { $0.fromCallsign == "N1CALL" })
        setup.model.deleteAPRSEvent(one)
        #expect(setup.model.conversations.map(\.peer) == ["N2CALL"])
        setup.model.deleteAllAPRSEvents()
        #expect(setup.model.conversations.isEmpty)
    }

    @Test("messages stay without limit by default, while other packets go; a time of their own can be set")
    func retention() async throws {
        #expect(AppSettings().messageRetentionDays == 0)
        #expect(AppSettings.messageRetentionOptions == [30, 90, 365, 0])
        var keepingInternet = AppSettings()
        keepingInternet.keepsInternetPackets = true
        let setup = try Setup(settings: keepingInternet)
        await setup.receive("N1CALL>APRS,TCPIP*::N0CALL   :Old message")
        await setup.receive("N2CALL>APRS,TCPIP*:>Old status")
        #expect(await KV4PTestSupport.eventually { setup.model.storedPacketCount == 2 })
        setup.time.advance(by: 31 * Self.day)
        setup.model.packetRetentionDays = 30
        #expect(await KV4PTestSupport.eventually { setup.model.storedPacketCount == 1 })
        #expect(setup.model.aprsEvents.map(\.body) == ["Old message"])
        #expect(setup.model.conversations.count == 1)
        setup.model.messageRetentionDays = 30
        #expect(await KV4PTestSupport.eventually { setup.model.storedPacketCount == 0 })
        #expect(setup.model.conversations.isEmpty)
        #expect(setup.settings.settings.messageRetentionDays == 30)
        #expect(!SettingsSync.values(of: AppSettings()).keys.contains("messageRetentionDays"))
    }

    @Test("without a callsign, old messages go with the other packets")
    func retentionWithoutCallsign() async throws {
        let setup = try Setup()
        await setup.receive("N1CALL>APRS,TCPIP*::N0CALL   :Old message")
        #expect(await KV4PTestSupport.eventually { setup.model.storedPacketCount == 1 })
        setup.model.callsign = ""
        setup.time.advance(by: 31 * Self.day)
        setup.model.packetRetentionDays = 30
        #expect(await KV4PTestSupport.eventually { setup.model.storedPacketCount == 0 })
    }

    @Test("the page is kept, and the chats know whether they last beyond the app")
    func page() throws {
        var stored = AppSettings()
        stored.aprsPage = .chats
        stored.isKeepingPackets = false
        let setup = try Setup(settings: stored)
        #expect(setup.model.aprsPage == .chats)
        #expect(!setup.model.isKeepingPackets)
        #expect(!SettingsSync.values(of: AppSettings()).keys.contains("aprsPage"))
    }
}
