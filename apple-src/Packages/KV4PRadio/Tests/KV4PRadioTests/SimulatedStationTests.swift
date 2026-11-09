import KV4PAPRS
import KV4PSimulator
import KV4PTestSupport
import Testing

@testable import KV4PRadio

/// The station the simulator plays, which answers messages as chosen (ADR-0061).
@Suite("Simulated station")
struct SimulatedStationTests {
    private static func packet(_ line: String) throws -> APRSPacket {
        try APRSParser.parse(tnc2: line)
    }

    private static let message = "N0CALL-7>APKVPA::N1CALL-5 :Hello{AB1"

    @Test("an acknowledgement comes after 2 s, and a reply after the chosen time, from the station written to")
    func answers() throws {
        let packet = try Self.packet(Self.message)
        let reply = Duration.seconds(30)
        #expect(
            SimulatedStation.answers(to: packet, with: .acknowledge, replyDelay: reply, isFirst: true) == [
                .init(delay: .seconds(2), tnc2: "N1CALL-5>APRS::N0CALL-7 :ackAB1")
            ]
        )
        #expect(
            SimulatedStation.answers(to: packet, with: .acknowledgeAndReply, replyDelay: reply, isFirst: true) == [
                .init(delay: .seconds(2), tnc2: "N1CALL-5>APRS::N0CALL-7 :ackAB1"),
                .init(delay: reply, tnc2: "N1CALL-5>APRS::N0CALL-7 :Test reply to your message AB1{AB1"),
            ]
        )
        #expect(
            SimulatedStation.answers(to: packet, with: .reject, replyDelay: reply, isFirst: true) == [
                .init(delay: .seconds(2), tnc2: "N1CALL-5>APRS::N0CALL-7 :rejAB1")
            ]
        )
        #expect(SimulatedStation.answers(to: packet, with: .none, replyDelay: reply, isFirst: true).isEmpty)
    }

    @Test("a repeat is acknowledged again, but brings no second reply")
    func repeats() throws {
        let answers = SimulatedStation.answers(
            to: try Self.packet(Self.message),
            with: .acknowledgeAndReply,
            replyDelay: .seconds(30),
            isFirst: false
        )
        #expect(answers.map(\.tnc2) == ["N1CALL-5>APRS::N0CALL-7 :ackAB1"])
    }

    @Test("bulletins, answers, messages without a number and other packets get nothing")
    func nothing() throws {
        for line in [
            "N0CALL>APKVPA::BLN1CQ   :To all",
            "N0CALL>APKVPA::N1CALL   :ackAB1",
            "N0CALL>APKVPA::N1CALL   :rejAB1",
            "N0CALL>APKVPA::N1CALL   :No number",
            "N0CALL>APKVPA:>Status",
        ] {
            #expect(
                SimulatedStation.answers(
                    to: try Self.packet(line),
                    with: .acknowledgeAndReply,
                    replyDelay: .zero,
                    isFirst: true
                )
                .isEmpty
            )
        }
    }

    @Test("the choices have names, and the delays to choose from")
    func choices() {
        #expect(SimulatedMessageAnswer.allCases.allSatisfy { !$0.label.isEmpty })
        #expect(AppSettings().simulatedMessageAnswer == .acknowledge)
        #expect(AppSettings().simulatedReplyDelaySeconds == 10)
        #expect(AppSettings.simulatedReplyDelayOptions == [2, 10, 30, 60, 300])
    }
}

/// The simulated station in the view model.
@MainActor
@Suite("Simulated station in the view model")
struct SimulatedStationModelTests {
    @MainActor
    private final class Setup {
        let radio = SimulatorRadio(clock: ManualClock(), isOverBluetooth: false)
        let store = MemorySettingsStore()
        let model: RadioViewModel

        init() {
            let radio = radio
            model = RadioViewModel(
                makeController: { _, rxAudio in
                    RadioController(transport: radio.makeTransport(), clock: ManualClock(), rxAudio: rxAudio)
                },
                serialDevices: { [] },
                settings: store,
                simulator: radio,
                simulatorAnswerSleep: { _ in }
            )
            model.callsign = "N0CALL"
        }

        func connect() async {
            model.selectedConnection = .simulator
            await model.connect()
            #expect(await RadioViewModelTests.eventually(model) { $0.isReady && $0.snapshot.isInSync })
        }
    }

    @Test("a message sent over the simulator is acknowledged, and with a reply, answered")
    func answered() async {
        let setup = Setup()
        await setup.connect()
        setup.model.sendChatMessage("Hello", to: "N1CALL")
        #expect(
            await RadioViewModelTests.eventually(setup.model) {
                $0.messages(with: "N1CALL").first?.deliveryState == .delivered
            }
        )

        setup.model.simulatedMessageAnswer = .acknowledgeAndReply
        setup.model.simulatedReplyDelaySeconds = 30
        #expect(setup.store.settings.simulatedMessageAnswer == .acknowledgeAndReply)
        #expect(setup.store.settings.simulatedReplyDelaySeconds == 30)
        setup.model.sendChatMessage("Again", to: "N1CALL")
        #expect(
            await RadioViewModelTests.eventually(setup.model) {
                $0.messages(with: "N1CALL").contains { $0.body?.hasPrefix("Test reply") == true }
            }
        )
    }

    @Test("a rejected message shows as rejected, and with no answer it waits")
    func rejected() async {
        let setup = Setup()
        await setup.connect()
        setup.model.simulatedMessageAnswer = .reject
        setup.model.sendChatMessage("Hello", to: "N1CALL")
        #expect(
            await RadioViewModelTests.eventually(setup.model) {
                $0.messages(with: "N1CALL").first?.deliveryState == .rejected
            }
        )
        setup.model.simulatedMessageAnswer = .none
        setup.model.sendChatMessage("Nobody", to: "N2CALL")
        try? await Task.sleep(for: .milliseconds(50))
        #expect(setup.model.messages(with: "N2CALL").first?.deliveryState == .pending)
    }

    @Test("the settings come back after a restart, and the simulator is not asked without a simulated radio")
    func settings() async {
        var stored = AppSettings()
        stored.simulatedMessageAnswer = .none
        stored.simulatedReplyDelaySeconds = 60
        let model = RadioViewModel(
            makeController: { _, _ in RadioController(transport: ScriptedTransport()) },
            serialDevices: { [] },
            settings: MemorySettingsStore(stored)
        )
        #expect(model.simulatedMessageAnswer == .none)
        #expect(model.simulatedReplyDelaySeconds == 60)
        #expect(!SettingsSync.values(of: AppSettings()).keys.contains("simulatedMessageAnswer"))
    }
}
