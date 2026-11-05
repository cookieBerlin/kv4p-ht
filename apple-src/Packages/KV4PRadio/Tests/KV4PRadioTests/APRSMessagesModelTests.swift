import KV4PAPRS
import KV4PPersistence
import KV4PTestSupport
import Testing

@testable import KV4PRadio

/// Records the notifications the view model asks for.
@MainActor
final class FakeMessageNotifier: APRSMessageNotifying {
    private(set) var delivered: [APRSMessageNotice] = []

    func deliver(_ notice: APRSMessageNotice) {
        delivered.append(notice)
    }
}

/// Replying, the count of new messages and their notifications (ADR-0058).
@MainActor
@Suite("APRS messages in the view model")
struct APRSMessagesModelTests {
    private static let toMe = "N1CALL>APRS,TCPIP*::N0CALL   :Hello"
    private static let toMe2 = "N2CALL>APRS,TCPIP*::N0CALL-7 :Again"
    private static let fromMe = "N0CALL>APRS,TCPIP*::N1CALL   :Hello"
    private static let toOther = "N1CALL>APRS,TCPIP*::N2CALL   :Hello"
    private static let bulletin = "N1CALL>APRS,TCPIP*::BLN1CQ   :Hello"
    private static let position = "N1CALL>APRS,TCPIP*:=4903.50N/07201.75W>Hello"

    @MainActor
    private final class Setup {
        let link = FakeLink()
        let notifier = FakeMessageNotifier()
        let permissions = FakePermissions()
        let settings: MemorySettingsStore
        let model: RadioViewModel

        init(history: (any APRSHistoryStoring)? = nil, settings: AppSettings = AppSettings()) {
            self.settings = MemorySettingsStore(settings)
            model = RadioViewModel(
                makeController: { _, _ in RadioController(transport: ScriptedTransport()) },
                serialDevices: { [] },
                internet: link,
                aprsHistory: history,
                settings: self.settings,
                messageNotifier: notifier,
                permissions: permissions,
                now: { 1_000 }
            )
            model.callsign = "N0CALL"
        }

        private var packets: Int {
            model.aprsEvents.reduce(0) { $0 + $1.packetCount }
        }

        /// Waits until each packet has reached the list.
        func receive(_ lines: String...) async {
            for line in lines {
                let before = packets
                link.receive.yield(line)
                #expect(await KV4PTestSupport.eventually { self.packets > before })
            }
        }
    }

    // MARK: Count

    @Test("a new message to this station counts while the list is not on screen")
    func counts() async {
        let setup = Setup()
        await setup.receive(Self.toMe, Self.toMe2)
        #expect(setup.model.newAPRSMessages == 2)
    }

    @Test("a repeat, other traffic, a bulletin and an own message do not count")
    func doesNotCount() async {
        let setup = Setup()
        await setup.receive(Self.toMe, Self.toMe, Self.toOther, Self.bulletin, Self.fromMe, Self.position)
        #expect(setup.model.newAPRSMessages == 1)
    }

    @Test("the count ends when a list comes on screen, and stays at 0 while it is there")
    func clears() async {
        let setup = Setup()
        await setup.receive(Self.toMe)
        setup.model.isAPRSVisible = true
        #expect(setup.model.newAPRSMessages == 0)
        await setup.receive(Self.toMe2)
        #expect(setup.model.newAPRSMessages == 0)
        setup.model.isAPRSVisible = false
        await setup.receive("N3CALL>APRS,TCPIP*::N0CALL   :Third")
        #expect(setup.model.newAPRSMessages == 1)
        setup.model.isPacketsPageVisible = true
        #expect(setup.model.newAPRSMessages == 0)
    }

    @Test("messages that come back from the store are not new")
    func restored() async throws {
        let history = try SwiftDataAPRSHistory.inMemory()
        let first = Setup(history: history)
        await first.receive(Self.toMe)
        #expect(await KV4PTestSupport.eventually { first.model.storedPacketCount == 1 })
        let second = Setup(history: history)
        #expect(await KV4PTestSupport.eventually { second.model.aprsEvents.count == 1 })
        second.model.isAppActive = false
        #expect(second.model.newAPRSMessages == 0)
        #expect(second.notifier.delivered.isEmpty)
    }

    // MARK: Notification

    @Test("in the background a new message brings one notification, with its sender and text")
    func notifies() async {
        let setup = Setup()
        setup.model.isAppActive = false
        await setup.receive(Self.toMe, Self.toMe)
        #expect(setup.notifier.delivered.map(\.title) == ["N1CALL"])
        #expect(setup.notifier.delivered.map(\.text) == ["Hello"])
        await setup.receive(Self.toMe2)
        #expect(Set(setup.notifier.delivered.map(\.id)).count == 2)
    }

    @Test("nothing is notified with the app on screen, for other traffic, or with the switch off")
    func doesNotNotify() async {
        let active = Setup()
        await active.receive(Self.toMe)
        #expect(active.notifier.delivered.isEmpty)

        let other = Setup()
        other.model.isAppActive = false
        await other.receive(Self.toOther, Self.bulletin, Self.fromMe, Self.position)
        #expect(other.notifier.delivered.isEmpty)

        let off = Setup()
        off.model.isAppActive = false
        off.model.notifiesAboutMessages = false
        await off.receive(Self.toMe)
        #expect(off.notifier.delivered.isEmpty)
        #expect(off.model.newAPRSMessages == 1)
    }

    @Test("the switch is on by default, is kept, and stays on this device")
    func setting() {
        #expect(AppSettings().notifiesAboutMessages)
        let setup = Setup()
        #expect(setup.model.notifiesAboutMessages)
        setup.model.notifiesAboutMessages = false
        #expect(!setup.settings.settings.notifiesAboutMessages)
        var stored = AppSettings()
        stored.notifiesAboutMessages = false
        #expect(!Setup(settings: stored).model.notifiesAboutMessages)
        #expect(!SettingsSync.values(of: AppSettings()).keys.contains("notifiesAboutMessages"))
    }

    @Test("connecting and turning the switch on ask for the permission, also with the simulator")
    func asksForPermission() async {
        let setup = Setup()
        setup.model.selectedConnection = .simulator
        await setup.model.connect()
        #expect(setup.permissions.requested == [.notifications])
        setup.model.notifiesAboutMessages = false
        setup.model.notifiesAboutMessages = true
        #expect(setup.permissions.requested == [.notifications, .notifications])
    }

    @Test("with the switch off, connecting does not ask")
    func doesNotAsk() async {
        var stored = AppSettings()
        stored.notifiesAboutMessages = false
        let setup = Setup(settings: stored)
        setup.model.selectedConnection = .simulator
        await setup.model.connect()
        #expect(setup.permissions.requested.isEmpty)
    }

    // MARK: Reply

    @Test("replying fills in the sender, or for an own message its recipient")
    func replies() async throws {
        let setup = Setup()
        await setup.receive(Self.toMe2, Self.fromMe)
        let events = setup.model.aprsEvents
        let received = events.first { $0.fromCallsign == "N2CALL" }
        let sent = events.first { $0.fromCallsign == "N0CALL" }
        setup.model.reply(to: try #require(received))
        #expect(setup.model.aprsRecipient == "N2CALL")
        #expect(setup.model.aprsReplyCount == 1)
        setup.model.reply(to: try #require(sent))
        #expect(setup.model.aprsRecipient == "N1CALL")
        #expect(setup.model.aprsReplyCount == 2)
    }

    @Test("only a message can be replied to, and only by a station that can send")
    func canReply() async throws {
        let setup = Setup()
        await setup.receive(Self.toMe, Self.position)
        let message = setup.model.aprsEvents.first { $0.kind == .message }
        let position = setup.model.aprsEvents.first { $0.kind == .position }
        #expect(setup.model.canReply(to: try #require(message)))
        #expect(!setup.model.canReply(to: try #require(position)))
        setup.model.reply(to: try #require(position))
        #expect(setup.model.aprsRecipient.isEmpty)
        #expect(setup.model.aprsReplyCount == 0)
        setup.model.isListenOnly = true
        #expect(!setup.model.canReply(to: try #require(message)))
    }
}
