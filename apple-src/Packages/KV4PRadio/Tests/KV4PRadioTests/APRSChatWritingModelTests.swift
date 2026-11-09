import KV4PAPRS
import KV4PPersistence
import KV4PSimulator
import KV4PTestSupport
import Testing

@testable import KV4PRadio

/// Writing in chats in the view model: sending, sending again and deleting (ADR-0061, 4.7b).
@MainActor
@Suite("APRS chats: writing in the view model")
struct APRSChatWritingModelTests {
    @MainActor
    private final class Setup {
        let time = TestTime()
        let link = FakeLink()
        let history: any APRSHistoryStoring
        let model: RadioViewModel

        init(listLimit: Int = 500) throws {
            history = try SwiftDataAPRSHistory.inMemory()
            let time = time
            model = RadioViewModel(
                makeController: { _, rxAudio in
                    let clock = ManualClock()
                    let transport = SimulatorTransport(simulator: RadioSimulator(scenario: .ble), clock: clock)
                    return RadioController(transport: transport, clock: clock, rxAudio: rxAudio)
                },
                serialDevices: { [] },
                internet: link,
                aprsHistory: history,
                now: { time.ms },
                aprsTickInterval: .milliseconds(1),
                aprsListLimit: listLimit
            )
            model.callsign = "N0CALL"
            model.selectedConnection = .simulator
        }

        /// Ready to transmit on 144.800 MHz.
        func ready() async {
            await model.connect()
            #expect(await KV4PTestSupport.eventually { self.model.isReady })
            model.frequencyText = "144.8"
            await model.applyFrequency()
            #expect(await KV4PTestSupport.eventually { self.model.canTransmit && self.model.snapshot.isInSync })
        }

        /// Sends, and lets every retry pass without an answer.
        func failedMessage(_ text: String) async throws -> APRSEvent {
            model.sendChatMessage(text, to: "N1CALL")
            let sent = try #require(model.messages(with: "N1CALL").last)
            #expect(sent.deliveryState == .pending)
            #expect(
                await KV4PTestSupport.eventually {
                    self.time.advance(by: 60_000)
                    return self.model.messages(with: "N1CALL").last?.deliveryState == .failed
                }
            )
            return try #require(model.messages(with: "N1CALL").last)
        }
    }

    @Test("a chat message goes to its station, and the limit keeps it whole")
    func sends() async throws {
        let setup = try Setup()
        await setup.ready()
        #expect(setup.model.chatTextLimit(for: "N1CALL") == 61)
        setup.model.sendChatMessage(String(repeating: "x", count: 70), to: "N1CALL")
        let sent = try #require(setup.model.messages(with: "N1CALL").last)
        #expect(sent.body == String(repeating: "x", count: 61))
        #expect(sent.toCallsign == "N1CALL")
    }

    @Test("a message not delivered can be sent again, which replaces it in the chat and keeps it in the packets")
    func resends() async throws {
        let setup = try Setup()
        await setup.ready()
        let failed = try await setup.failedMessage("Hello")
        #expect(setup.model.canResend(failed))
        setup.model.resend(failed)
        let messages = setup.model.messages(with: "N1CALL")
        #expect(messages.count == 1)
        #expect(messages[0].deliveryState == .pending)
        #expect(messages[0].body == "Hello")
        #expect(setup.model.aprsEvents.filter { $0.body == "Hello" }.count == 2)
        #expect(!setup.model.canResend(messages[0]))
    }

    @Test("a message no longer in memory is sent again as well, and stays out of the chat after a restart")
    func resendsStored() async throws {
        let setup = try Setup(listLimit: 1)
        await setup.ready()
        let failed = try await setup.failedMessage("Old")
        setup.link.receive.yield("N3CALL>APRS,TCPIP*:>Pushes it out")
        #expect(await KV4PTestSupport.eventually { !setup.model.aprsEvents.contains { $0.id == failed.id } })
        setup.model.resend(failed)
        #expect(setup.model.messages(with: "N1CALL").map(\.deliveryState) == [.pending])
        #expect(
            await KV4PTestSupport.eventually {
                let page = (try? await setup.history.page(before: nil, limit: 10)) ?? []
                return page.contains {
                    $0.id == failed.id && String(decoding: $0.payload, as: UTF8.self).contains("isResent")
                }
            }
        )
    }

    @Test("only own messages that were not delivered can be sent again, and only by a station that can send")
    func canResend() async throws {
        let setup = try Setup()
        await setup.ready()
        setup.link.receive.yield("N1CALL>APRS,TCPIP*::N0CALL   :Hi")
        #expect(await KV4PTestSupport.eventually { setup.model.messages(with: "N1CALL").count == 1 })
        let received = try #require(setup.model.messages(with: "N1CALL").first)
        #expect(!setup.model.canResend(received))
        setup.model.resend(received)
        #expect(setup.model.messages(with: "N1CALL").count == 1)
        let failed = try await setup.failedMessage("Mine")
        setup.model.isListenOnly = true
        #expect(!setup.model.canResend(failed))
    }

    @Test("sending again that is not accepted leaves the message as it was")
    func resendRefused() async throws {
        let setup = try Setup()
        await setup.ready()
        let failed = try await setup.failedMessage("Hello")
        await setup.model.disconnect()
        setup.model.resend(failed)
        #expect(setup.model.messages(with: "N1CALL").map(\.id) == [failed.id])
        #expect(setup.model.message != nil)
    }

    @Test("a whole chat can be deleted, also from the packets, and closes")
    func deletesChat() async throws {
        let setup = try Setup()
        setup.link.receive.yield("N1CALL>APRS,TCPIP*::N0CALL   :One")
        setup.link.receive.yield("N2CALL>APRS,TCPIP*::N0CALL   :Two")
        #expect(await KV4PTestSupport.eventually { setup.model.conversations.count == 2 })
        #expect(await KV4PTestSupport.eventually { setup.model.storedPacketCount == 2 })
        setup.model.openChat = "N1CALL"
        setup.model.deleteChat(with: "N1CALL")
        #expect(setup.model.openChat == nil)
        #expect(setup.model.conversations.map(\.peer) == ["N2CALL"])
        #expect(!setup.model.aprsEvents.contains { $0.fromCallsign == "N1CALL" })
        #expect(await KV4PTestSupport.eventually { setup.model.storedPacketCount == 1 })
        setup.model.openChat = "N2CALL"
        setup.model.deleteChat(with: "N1CALL")
        #expect(setup.model.openChat == "N2CALL")
    }
}
