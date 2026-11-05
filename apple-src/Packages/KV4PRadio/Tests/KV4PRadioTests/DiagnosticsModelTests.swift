import Foundation
import KV4PAudio
import KV4PSimulator
import KV4PTestSupport
import KV4PTransport
import Testing

@testable import KV4PRadio

/// What the view model logs, and the way to a report (ADR-0059).
@MainActor
@Suite("Diagnostics in the view model")
struct DiagnosticsModelTests {
    private static let day: Int64 = 86_400_000
    private static let environment = ProblemReport.Environment(version: "1.2", device: "Device", system: "System")

    @MainActor
    private final class Setup {
        let store = MemoryLogStore()
        let time = TestTime()
        let link = FakeLink()
        let permissions = FakePermissions()
        let settings = MemorySettingsStore(AppSettings())
        let crashes: CrashReportStore
        let log: DiagnosticLog
        let model: RadioViewModel

        init(crashes: CrashReportStore? = nil) {
            let time = time
            self.crashes =
                crashes ?? CrashReportStore(folder: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
            log = DiagnosticLog(store: store, now: { time.ms })
            model = RadioViewModel(
                makeController: { _, rxAudio in
                    let clock = ManualClock()
                    let transport = SimulatorTransport(simulator: RadioSimulator(scenario: .ble), clock: clock)
                    return RadioController(transport: transport, clock: clock, rxAudio: rxAudio)
                },
                serialDevices: { [] },
                internet: link,
                settings: settings,
                permissions: permissions,
                diagnostics: log,
                crashReports: self.crashes,
                now: { time.ms }
            )
        }

        var text: String { store.read() }

        func waits(for part: String) async -> Bool {
            await KV4PTestSupport.eventually { [store] in store.read().contains(part) }
        }
    }

    @Test("a connection logs how it goes, with the firmware but not the name of the radio")
    func connection() async {
        let setup = Setup()
        setup.model.selectedConnection = .simulator
        await setup.model.connect()
        #expect(setup.text.contains("INFO connection: Connecting over simulator"))
        #expect(await setup.waits(for: "INFO connection: Status: ready"))
        #expect(await setup.waits(for: "INFO connection: Firmware "))
        await setup.model.disconnect()
        #expect(setup.text.contains("INFO connection: Disconnected"))
    }

    @Test("what the user is told is logged too")
    func notices() async {
        let setup = Setup()
        setup.model.sendAPRSMessage(to: "N1CALL", text: "Secret")
        #expect(setup.text.contains("INFO app: Set your callsign to send APRS messages."))
        #expect(!setup.text.contains("Secret"))
    }

    @Test("a refused permission is logged once")
    func permissions() {
        let setup = Setup()
        setup.permissions.setQuietly(.location, .denied)
        setup.model.refreshPermissions()
        setup.model.refreshPermissions()
        let lines = setup.text.components(separatedBy: "\n").filter { $0.contains("permissions: Refused: location") }
        #expect(lines.count == 1)
    }

    @Test("with details on, packets are told by their kind, without callsigns or text")
    func packets() async {
        let setup = Setup()
        setup.model.callsign = "N0CALL"
        setup.link.receive.yield("N1CALL>APRS,TCPIP*::N0CALL   :Secret")
        #expect(await KV4PTestSupport.eventually { setup.model.aprsEvents.count == 1 })
        #expect(!setup.text.contains("aprs:"))
        setup.model.isDetailedLogging = true
        setup.link.receive.yield("N2CALL>APRS,TCPIP*:=4903.50N/07201.75W>Hello")
        #expect(await setup.waits(for: "DETAIL aprs: Packet: position"))
        #expect(!setup.text.contains("N1CALL"))
        #expect(!setup.text.contains("N2CALL"))
        #expect(!setup.text.contains("Secret"))
        #expect(!setup.text.contains("4903"))
    }

    @Test("detailed logging ends by itself after a day, and is kept until then")
    func detailedLogging() {
        let setup = Setup()
        #expect(!setup.model.isDetailedLogging)
        setup.model.isDetailedLogging = true
        #expect(setup.model.isDetailedLogging)
        #expect(setup.settings.settings.detailedLoggingUntilMs == Self.day)
        #expect(!SettingsSync.values(of: AppSettings()).keys.contains("detailedLoggingUntilMs"))
        setup.time.advance(by: Self.day)
        #expect(!setup.model.isDetailedLogging)
        setup.model.isDetailedLogging = true
        setup.model.isDetailedLogging = false
        #expect(!setup.model.isDetailedLogging)
        #expect(setup.log.detailedUntilMs == 0)
    }

    @Test("the setting comes back after a restart")
    func restoresDetailedLogging() {
        var stored = AppSettings()
        stored.detailedLoggingUntilMs = Self.day
        let log = DiagnosticLog(store: MemoryLogStore(), now: { 0 })
        let model = RadioViewModel(
            makeController: { _, _ in RadioController(transport: ScriptedTransport()) },
            serialDevices: { [] },
            settings: MemorySettingsStore(stored),
            diagnostics: log,
            now: { 0 }
        )
        #expect(model.isDetailedLogging)
        #expect(log.detailedUntilMs == Self.day)
    }

    @Test("a new crash is offered once, also one from an earlier start")
    func offersCrash() {
        let setup = Setup()
        #expect(!setup.model.offersCrashReport)
        setup.model.receiveCrashReport(id: "1", json: "{}")
        #expect(setup.model.offersCrashReport)
        setup.model.dismissCrashOffer()
        #expect(!setup.model.offersCrashReport)
        setup.model.receiveCrashReport(id: "1", json: "{}")
        #expect(!setup.model.offersCrashReport)
        #expect(setup.text.contains("ERROR app: A crash was reported"))

        let store = CrashReportStore(folder: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        #expect(store.add(id: "2", json: "{}"))
        #expect(Setup(crashes: store).model.offersCrashReport)
    }

    @Test("the report holds the log and crashes, without the callsign, and the firmware stays after disconnecting")
    func report() async {
        let setup = Setup()
        #expect(setup.model.problemReport(in: Self.environment).contains("Firmware: Not connected yet"))
        setup.model.callsign = "N0CALL"
        setup.log.log(.info, .app, "Heard n0call-7")
        setup.model.receiveCrashReport(id: "1", json: "{\"crash\":\"data\"}")
        setup.model.selectedConnection = .simulator
        await setup.model.connect()
        #expect(await setup.waits(for: "Firmware "))
        await setup.model.disconnect()
        let text = setup.model.problemReport(in: Self.environment)
        #expect(text.contains("App: 1.2"))
        #expect(text.contains("[callsign]-7"))
        #expect(!text.uppercased().contains("N0CALL"))
        #expect(text.contains("{\"crash\":\"data\"}"))
        #expect(!text.contains("Firmware: Not connected yet"))
        #expect(setup.model.problemIssueURL(in: Self.environment) != nil)
    }

    @Test("deleting removes the log and the crashes")
    func deletes() {
        let setup = Setup()
        setup.log.log(.info, .app, "A line")
        setup.model.receiveCrashReport(id: "1", json: "crash")
        setup.model.deleteDiagnostics()
        #expect(setup.text.isEmpty)
        #expect(setup.crashes.all().isEmpty)
        #expect(!setup.model.offersCrashReport)
    }

    @Test("without a log or crash store, nothing breaks")
    func without() {
        let model = RadioViewModel(
            makeController: { _, _ in RadioController(transport: ScriptedTransport()) },
            serialDevices: { [] }
        )
        model.receiveCrashReport(id: "1", json: "{}")
        #expect(!model.offersCrashReport)
        model.dismissCrashOffer()
        model.deleteDiagnostics()
        #expect(model.problemReport(in: Self.environment).contains("Crashes: none reported"))
    }
}
