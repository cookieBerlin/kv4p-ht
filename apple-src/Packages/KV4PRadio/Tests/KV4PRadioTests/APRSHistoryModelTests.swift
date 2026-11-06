import Foundation
import KV4PAPRS
import KV4PPersistence
import KV4PTestSupport
import Testing

@testable import KV4PRadio

/// What the view model keeps of the APRS list across restarts (ADR-0057).
@MainActor
@Suite("APRS history in the view model")
struct APRSHistoryModelTests {
    private struct FailingHistory: APRSHistoryStoring {
        struct Failure: Error {}
        func save(_ entries: [APRSHistoryEntry]) async throws { throw Failure() }
        func page(before lastSeenMs: Int64?, limit: Int) async throws -> [APRSHistoryEntry] { throw Failure() }
        func delete(id: Int64) async throws { throw Failure() }
        func deleteOlder(than lastSeenMs: Int64) async throws { throw Failure() }
        func deleteAll() async throws { throw Failure() }
        func count() async throws -> Int { throw Failure() }
        func highestId() async throws -> Int64 { throw Failure() }
    }

    private static let day: Int64 = 86_400_000
    private static let position = "N1CALL>APRS,TCPIP*:=4903.50N/07201.75W>Hello"
    private static let toMe = "N1CALL>APRS,TCPIP*::N0CALL   :Hello"
    private static let fromMe = "N0CALL>APRS,TCPIP*::N1CALL   :Hello"
    private static let toOther = "N1CALL>APRS,TCPIP*::N2CALL   :Hello"

    @MainActor
    private final class Setup {
        let link = FakeLink()
        let time = TestTime()
        let settings: MemorySettingsStore
        let history: any APRSHistoryStoring
        let model: RadioViewModel

        init(
            history: (any APRSHistoryStoring)? = nil,
            settings: AppSettings = AppSettings(),
            listLimit: Int = 500,
            start: Int64 = 0
        ) throws {
            self.history = try history ?? SwiftDataAPRSHistory.inMemory()
            self.settings = MemorySettingsStore(settings)
            time.advance(by: start)
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

        func receive(_ line: String, atOffset offset: Int64 = 100_000) async {
            let before = model.aprsEvents.map(\.lastSeenMs)
            time.advance(by: offset)
            link.receive.yield(line)
            #expect(await KV4PTestSupport.eventually { self.model.aprsEvents.map(\.lastSeenMs) != before })
        }

        func stored() async -> Int {
            (try? await history.count()) ?? -1
        }

        func waitForStored(_ count: Int) async -> Bool {
            await KV4PTestSupport.eventually { [self] in
                let current = await stored()
                return current == count
            }
        }
    }

    private static func keepingInternet() -> AppSettings {
        var settings = AppSettings()
        settings.keepsInternetPackets = true
        return settings
    }

    @Test("the defaults keep packets for 30 days, but not those only from the internet")
    func defaults() {
        let settings = AppSettings()
        #expect(settings.isKeepingPackets)
        #expect(!settings.keepsInternetPackets)
        #expect(settings.packetRetentionDays == 30)
        #expect(AppSettings.packetRetentionOptions == [1, 7, 30, 0])
    }

    @Test("the settings are kept, and stay on this device")
    func settings() throws {
        let setup = try Setup()
        setup.model.isKeepingPackets = false
        setup.model.keepsInternetPackets = true
        setup.model.packetRetentionDays = 7
        #expect(!setup.settings.settings.isKeepingPackets)
        #expect(setup.settings.settings.keepsInternetPackets)
        #expect(setup.settings.settings.packetRetentionDays == 7)
        var stored = AppSettings()
        stored.isKeepingPackets = false
        stored.keepsInternetPackets = true
        stored.packetRetentionDays = 1
        let restored = try Setup(settings: stored)
        #expect(!restored.model.isKeepingPackets)
        #expect(restored.model.keepsInternetPackets)
        #expect(restored.model.packetRetentionDays == 1)
        let keys = SettingsSync.values(of: AppSettings()).keys
        #expect(!keys.contains("isKeepingPackets"))
        #expect(!keys.contains("keepsInternetPackets"))
        #expect(!keys.contains("packetRetentionDays"))
    }

    @Test("packets only from the internet stay in the list, but are not stored by default")
    func internetNotStored() async throws {
        let setup = try Setup()
        await setup.receive(Self.position)
        await setup.receive(Self.toOther)
        #expect(setup.model.aprsEvents.count == 2)
        #expect(await setup.stored() == 0)
    }

    @Test("with the switch on, they are stored as well")
    func internetStored() async throws {
        let setup = try Setup(settings: Self.keepingInternet())
        await setup.receive(Self.position)
        #expect(await setup.waitForStored(1))
        #expect(await KV4PTestSupport.eventually { setup.model.storedPacketCount == 1 })
    }

    @Test("messages to or from this station are always stored")
    func messagesStored() async throws {
        let setup = try Setup()
        await setup.receive(Self.toMe)
        #expect(await setup.waitForStored(1))
        await setup.receive(Self.fromMe)
        #expect(await setup.waitForStored(2))
    }

    @Test("a repeat updates the stored packet")
    func repeats() async throws {
        let setup = try Setup(settings: Self.keepingInternet())
        await setup.receive(Self.position)
        #expect(await setup.waitForStored(1))
        await setup.receive(Self.position, atOffset: 1_000)
        #expect(setup.model.aprsEvents.first?.packetCount == 2)
        let expected = setup.time.ms
        let saved = await KV4PTestSupport.eventually { [history = setup.history] in
            let page = (try? await history.page(before: nil, limit: 1)) ?? []
            return page.first?.lastSeenMs == expected
        }
        #expect(saved)
        #expect(await setup.stored() == 1)
    }

    @Test("after a restart the list is back, and new packets get new ids")
    func restart() async throws {
        let first = try Setup(settings: Self.keepingInternet())
        await first.receive(Self.position)
        #expect(await first.waitForStored(1))
        let second = try Setup(history: first.history, settings: Self.keepingInternet(), start: 200_000)
        #expect(await KV4PTestSupport.eventually { second.model.aprsEvents.count == 1 })
        #expect(second.model.aprsEvents.first == first.model.aprsEvents.first)
        await second.receive(Self.toOther)
        #expect(Set(second.model.aprsEvents.map(\.id)).count == 2)
        #expect(await second.waitForStored(2))
    }

    @Test("switched off, nothing is stored and nothing comes back")
    func off() async throws {
        var settings = Self.keepingInternet()
        settings.isKeepingPackets = false
        let history = try SwiftDataAPRSHistory.inMemory()
        let entry = APRSHistoryEntry(
            id: 1,
            lastSeenMs: 1,
            kind: 3,
            fromCallsign: "N1CALL",
            toCallsign: nil,
            isInternetOnly: false,
            payload: Data()
        )
        try await history.save([entry])
        let setup = try Setup(history: history, settings: settings)
        await setup.receive(Self.position)
        #expect(setup.model.aprsEvents.count == 1)
        #expect(await setup.stored() == 1)
        #expect(!setup.model.hasMoreAPRSHistory)
    }

    @Test("what cannot be read any more is left out")
    func unreadable() async throws {
        let history = try SwiftDataAPRSHistory.inMemory()
        let entry = APRSHistoryEntry(
            id: 1,
            lastSeenMs: 1,
            kind: 3,
            fromCallsign: "N1CALL",
            toCallsign: nil,
            isInternetOnly: false,
            payload: Data("not an event".utf8)
        )
        try await history.save([entry])
        let setup = try Setup(history: history)
        #expect(await KV4PTestSupport.eventually { setup.model.storedPacketCount == 1 })
        #expect(setup.model.aprsEvents.isEmpty)
    }

    @Test("a single packet can go")
    func deleteOne() async throws {
        let setup = try Setup(settings: Self.keepingInternet())
        await setup.receive(Self.position)
        await setup.receive(Self.toOther)
        #expect(await setup.waitForStored(2))
        let event = try #require(setup.model.aprsEvents.last)
        setup.model.deleteAPRSEvent(event)
        #expect(setup.model.aprsEvents.count == 1)
        #expect(await setup.waitForStored(1))
    }

    @Test("all packets can go")
    func deleteAll() async throws {
        let setup = try Setup(settings: Self.keepingInternet())
        await setup.receive(Self.position)
        #expect(await setup.waitForStored(1))
        setup.model.deleteAllAPRSEvents()
        #expect(setup.model.aprsEvents.isEmpty)
        #expect(await setup.waitForStored(0))
        #expect(await KV4PTestSupport.eventually { setup.model.storedPacketCount == 0 })
    }

    @Test("switching off leaves what is stored, unless the user deletes it")
    func offKeepsStored() async throws {
        let setup = try Setup(settings: Self.keepingInternet())
        await setup.receive(Self.position)
        #expect(await setup.waitForStored(1))
        setup.model.isKeepingPackets = false
        await setup.receive(Self.toOther)
        #expect(await setup.stored() == 1)
        #expect(setup.model.aprsEvents.count == 2)
    }

    @Test("old packets go at the start and when the time is shortened")
    func retention() async throws {
        let history = try SwiftDataAPRSHistory.inMemory()
        var settings = Self.keepingInternet()
        settings.packetRetentionDays = 30
        let first = try Setup(history: history, settings: settings)
        await first.receive(Self.position)
        #expect(await first.waitForStored(1))

        // Ten days later, 30 days still keep it.
        let later = try Setup(history: history, settings: settings, start: 10 * Self.day)
        #expect(await KV4PTestSupport.eventually { later.model.aprsEvents.count == 1 })
        #expect(await later.stored() == 1)
        later.model.packetRetentionDays = 7
        #expect(await later.waitForStored(0))
        #expect(later.model.aprsEvents.isEmpty)

        // No limit keeps all, also what is very old.
        var forever = Self.keepingInternet()
        forever.packetRetentionDays = 0
        let keeping = try Setup(history: history, settings: forever)
        await keeping.receive(Self.position)
        #expect(await keeping.waitForStored(1))
        let muchLater = try Setup(history: history, settings: forever, start: 1000 * Self.day)
        #expect(await KV4PTestSupport.eventually { muchLater.model.aprsEvents.count == 1 })
        #expect(await muchLater.stored() == 1)
    }

    @Test("old packets also go while the app runs")
    func retentionWhileRunning() async throws {
        var settings = Self.keepingInternet()
        settings.packetRetentionDays = 1
        let setup = try Setup(settings: settings)
        await setup.receive(Self.position)
        #expect(await setup.waitForStored(1))
        setup.time.advance(by: 2 * Self.day)
        await setup.receive(Self.toOther)
        #expect(await setup.waitForStored(1))
        #expect(setup.model.aprsEvents.count == 1)
    }

    @Test("the list holds the newest, and more can be loaded")
    func loadMore() async throws {
        let setup = try Setup(settings: Self.keepingInternet(), listLimit: 2)
        for index in 1...5 {
            await setup.receive("N\(index)CALL>APRS,TCPIP*:>Status")
        }
        #expect(await setup.waitForStored(5))
        let restarted = try Setup(
            history: setup.history,
            settings: Self.keepingInternet(),
            listLimit: 2,
            start: 600_000
        )
        #expect(await KV4PTestSupport.eventually { restarted.model.aprsEvents.count == 2 })
        #expect(restarted.model.hasMoreAPRSHistory)
        await restarted.model.loadMoreAPRSHistory()
        #expect(restarted.model.aprsEvents.count > 2)
        while restarted.model.hasMoreAPRSHistory {
            await restarted.model.loadMoreAPRSHistory()
        }
        #expect(restarted.model.aprsEvents.count == 5)
        #expect(restarted.model.aprsEvents.map(\.fromCallsign).first == "N5CALL")
        let old = try #require(restarted.model.aprsEvents.last)
        restarted.model.deleteAPRSEvent(old)
        #expect(restarted.model.aprsEvents.count == 4)
    }

    @Test("a shorter time also takes older packets out of the list")
    func retentionOfLoaded() async throws {
        var settings = Self.keepingInternet()
        settings.packetRetentionDays = 0
        let setup = try Setup(settings: settings, listLimit: 1)
        await setup.receive("N1CALL>APRS,TCPIP*:>Status")
        await setup.receive("N2CALL>APRS,TCPIP*:>Status")
        #expect(await setup.waitForStored(2))
        let restarted = try Setup(history: setup.history, settings: settings, listLimit: 1, start: 3 * Self.day)
        #expect(await KV4PTestSupport.eventually { restarted.model.aprsEvents.count == 1 })
        await restarted.model.loadMoreAPRSHistory()
        #expect(restarted.model.aprsEvents.count == 2)
        restarted.model.packetRetentionDays = 1
        #expect(await KV4PTestSupport.eventually { restarted.model.aprsEvents.isEmpty })
        #expect(await restarted.waitForStored(0))
    }

    @Test("while the app runs, memory holds the newest; the rest stays stored and can be loaded")
    func trimsWhileRunning() async throws {
        let setup = try Setup(settings: Self.keepingInternet(), listLimit: 2)
        for index in 1...5 {
            await setup.receive("N\(index)CALL>APRS,TCPIP*:>Status")
        }
        #expect(await setup.waitForStored(5))
        #expect(setup.model.aprsEvents.count <= 4)
        #expect(setup.model.hasMoreAPRSHistory)
        while setup.model.hasMoreAPRSHistory {
            await setup.model.loadMoreAPRSHistory()
        }
        #expect(setup.model.aprsEvents.count == 5)
    }

    @Test("a model without a store has no history")
    func noHistory() async {
        let model = RadioViewModel(
            makeController: { _, _ in RadioController(transport: ScriptedTransport()) },
            serialDevices: { [] }
        )
        #expect(!model.hasMoreAPRSHistory)
        await model.loadMoreAPRSHistory()
        model.deleteAllAPRSEvents()
        #expect(model.storedPacketCount == 0)
    }

    @Test("a store that fails says so, and the list goes on")
    func failure() async throws {
        let setup = try Setup(history: FailingHistory(), settings: Self.keepingInternet())
        #expect(await KV4PTestSupport.eventually { setup.model.message != nil })
        setup.model.dismissNotice()
        setup.link.receive.yield(Self.position)
        #expect(await KV4PTestSupport.eventually { setup.model.aprsEvents.count == 1 })
        #expect(await KV4PTestSupport.eventually { setup.model.message != nil })
        setup.model.dismissNotice()
        await setup.model.loadMoreAPRSHistory()
        #expect(setup.model.message != nil)
    }
}
