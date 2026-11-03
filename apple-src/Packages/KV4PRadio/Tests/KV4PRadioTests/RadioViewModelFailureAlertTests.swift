import KV4PSimulator
import KV4PTestSupport
import KV4PTransport
import Testing

@testable import KV4PRadio

/// Records what the view model asks the platform to do.
@MainActor
final class FakeFailureAlerts: FailureAlerting {
    let usesDialog: Bool
    private(set) var prepared = 0
    private(set) var delivered: [String] = []

    init(usesDialog: Bool) {
        self.usesDialog = usesDialog
    }

    func prepare() {
        prepared += 1
    }

    func deliver(_ message: String) {
        delivered.append(message)
    }
}

/// Telling the user that the connection failed, also while the app is in the background (ADR-0039).
@MainActor
@Suite("Radio view model: failure alerts")
struct RadioViewModelFailureAlertTests {
    static let lost = "The connection to the radio was lost."

    /// Every connection uses a new transport, which the test makes fail.
    @MainActor
    final class Setup {
        let alerts: FakeFailureAlerts
        let model: RadioViewModel
        private let box = Box<ScriptedTransport>()

        init(usesDialog: Bool = true, connectError: TransportError? = nil) {
            let alerts = FakeFailureAlerts(usesDialog: usesDialog)
            let box = box
            self.alerts = alerts
            model = RadioViewModel(
                makeController: { _, rxAudio in
                    let transport = ScriptedTransport(connectError: connectError)
                    box.value = transport
                    return RadioController(transport: transport, clock: ManualClock(), rxAudio: rxAudio)
                },
                serialDevices: { [] },
                failureAlerts: alerts
            )
        }

        func loseConnection() {
            box.value?.streams.publish(.failed(.connectionLost))
        }

        func lostConnection() async {
            loseConnection()
            #expect(await KV4PTestSupport.eventually { self.alerts.delivered.count > 0 })
        }

        func connected() async {
            await model.connect()
            #expect(await KV4PTestSupport.eventually { self.model.snapshot.status == .waitingForHello })
        }
    }

    @Test("the Mac reports a lost connection in a dialog and through the platform")
    func dialogPlatform() async {
        let setup = Setup(usesDialog: true)
        await setup.connected()
        await setup.lostConnection()
        #expect(setup.alerts.delivered == [Self.lost])
        #expect(setup.model.alertMessage == Self.lost)
        #expect(setup.model.notice == nil)
    }

    @Test("iPhone and iPad show a lost connection once, as the status, and report it through the platform")
    func statusPlatform() async {
        let setup = Setup(usesDialog: false)
        await setup.connected()
        await setup.lostConnection()
        #expect(setup.alerts.delivered == [Self.lost])
        #expect(setup.model.alertMessage == nil)
        #expect(setup.model.notice == nil)
        #expect(setup.model.statusText == Self.lost)
    }

    @Test("a connection that cannot be set up is reported")
    func connectFails() async {
        let setup = Setup(connectError: .serviceNotFound)
        await setup.model.connect()
        #expect(await KV4PTestSupport.eventually { setup.alerts.delivered.count > 0 })
        #expect(setup.alerts.delivered == [setup.model.statusText])
    }

    @Test("one failure causes one report")
    func oneReport() async {
        let setup = Setup()
        await setup.connected()
        await setup.lostConnection()
        await setup.model.handle(.deviceUnavailable)  // shows the failed snapshot again
        #expect(setup.alerts.delivered.count == 1)
    }

    @Test("a new connection that fails is reported again")
    func newFailure() async {
        let setup = Setup()
        await setup.connected()
        await setup.lostConnection()
        await setup.connected()
        setup.loseConnection()
        #expect(await KV4PTestSupport.eventually { setup.alerts.delivered.count == 2 })
    }

    @Test("a disconnect the user chose causes no report")
    func chosenDisconnect() async {
        let setup = Setup()
        await setup.connected()
        await setup.model.disconnect()
        #expect(setup.model.statusText == "Not connected")
        #expect(setup.alerts.delivered.isEmpty)
        #expect(setup.model.alertMessage == nil)
    }

    @Test("connecting prepares the platform, each time")
    func prepares() async {
        let setup = Setup()
        #expect(setup.alerts.prepared == 0)
        await setup.connected()
        #expect(setup.alerts.prepared == 1)
        await setup.connected()
        #expect(setup.alerts.prepared == 2)
    }

    @Test("the dialog can be dismissed, and the status stays")
    func dismiss() async {
        let setup = Setup()
        await setup.connected()
        await setup.lostConnection()
        setup.model.dismissAlert()
        #expect(setup.model.alertMessage == nil)
        #expect(setup.model.statusText == Self.lost)
    }

    @Test("without a platform adapter, a failure shows as the status")
    func noAdapter() async {
        let model = RadioViewModelTests.model(.noRadioModule)
        await model.connect()
        #expect(await KV4PTestSupport.eventually { model.hasFailed })
        #expect(model.notice == nil)
        #expect(model.alertMessage == nil)
    }
}
