import Testing

@testable import KV4PRadio

/// What the connection offers where PTT stands while no radio is connected: connect, cancel or disconnect (ADR-0075).
@MainActor
@Suite("Connection action")
struct ConnectionActionTests {
    nonisolated private static let cases: [(RadioStatus, ConnectionAction)] = [
        (.disconnected, .connect),
        (.failed(.helloTimeout), .connect),
        (.connecting, .cancel),
        (.waitingForHello, .cancel),
        (.ready, .disconnect),
    ]

    @Test("each state of the connection has its action", arguments: cases)
    func actions(status: RadioStatus, action: ConnectionAction) {
        #expect(ConnectionAction(status) == action)
    }

    @Test("the actions have their names")
    func titles() {
        #expect(ConnectionAction.connect.title == "Connect")
        #expect(ConnectionAction.cancel.title == "Cancel")
        #expect(ConnectionAction.disconnect.title == "Disconnect")
    }

    @Test("the model offers the action of its state, and runs it")
    func model() async {
        let model = RadioViewModelTests.model()
        #expect(model.connectionAction == .connect)
        await model.runConnectionAction()
        #expect(await RadioViewModelTests.eventually(model) { $0.isReady })
        #expect(model.connectionAction == .disconnect)
        await model.runConnectionAction()
        #expect(model.connectionAction == .connect)
    }
}
