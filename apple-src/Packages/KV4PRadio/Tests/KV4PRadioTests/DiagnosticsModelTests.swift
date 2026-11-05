import Foundation
import KV4PAPRS
import KV4PAudio
import KV4PPersistence
import KV4PSimulator
import KV4PTestSupport
import KV4PTransport
import Testing

@testable import KV4PProtocol
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

        init(crashes: CrashReportStore? = nil, microphone: FakeMicrophone = FakeMicrophone()) {
            let time = time
            self.crashes =
                crashes
                ?? CrashReportStore(folder: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
            log = DiagnosticLog(store: store, now: { time.ms })
            model = RadioViewModel(
                makeController: { _, rxAudio in
                    let clock = ManualClock()
                    let transport = SimulatorTransport(simulator: RadioSimulator(scenario: .ble), clock: clock)
                    return RadioController(transport: transport, clock: clock, rxAudio: rxAudio, microphone: microphone)
                },
                serialDevices: { [] },
                internet: link,
                settings: settings,
                permissions: permissions,
                diagnostics: log,
                crashReports: self.crashes,
                now: { time.ms },
                aprsTickInterval: .milliseconds(1)
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
        #expect(setup.settings.settings.detailedLoggingUntilMs == setup.time.ms + Self.day)
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

    @Test("the live log comes with the log, its filter is kept on this device, and copying leaves out the callsign")
    func liveLog() async throws {
        let setup = Setup()
        let live = try #require(setup.model.liveLog)
        #expect(!SettingsSync.values(of: AppSettings()).keys.contains("logFilter"))
        live.filter = LogFilter(search: "n0call")
        #expect(setup.settings.settings.logFilter == LogFilter(search: "n0call"))
        live.filter = LogFilter()
        setup.model.callsign = "N0CALL"
        setup.log.log(.info, .app, "Heard n0call-7")
        live.start()
        #expect(setup.model.liveLogText().contains("[callsign]-7"))
        #expect(!setup.model.liveLogText().uppercased().contains("N0CALL"))
        #expect(setup.model.logSummary?.byteCount == setup.store.read().utf8.count)
        setup.model.deleteDiagnostics()
        #expect(live.lines.isEmpty)
        live.stop()
    }

    @Test("a stored filter comes back, and the end of detailed logging is known")
    func restoresLiveLog() {
        var stored = AppSettings()
        stored.logFilter = LogFilter(search: "x")
        stored.detailedLoggingUntilMs = Self.day
        let model = RadioViewModel(
            makeController: { _, _ in RadioController(transport: ScriptedTransport()) },
            serialDevices: { [] },
            settings: MemorySettingsStore(stored),
            diagnostics: DiagnosticLog(store: MemoryLogStore(), now: { 0 }),
            now: { 0 }
        )
        #expect(model.liveLog?.filter == LogFilter(search: "x"))
        #expect(model.detailedLoggingEnds == Date(timeIntervalSince1970: Double(Self.day) / 1000))
        model.isDetailedLogging = false
        #expect(model.detailedLoggingEnds == nil)
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
        #expect(model.liveLog == nil)
        #expect(model.logSummary == nil)
        #expect(model.liveLogText().isEmpty)
        #expect(model.problemReport(in: Self.environment).contains("Crashes: none reported"))
    }

    // MARK: Why something did not happen

    /// A radio that connects but never says HELLO, so that it stays not ready.
    private final class SilentSetup {
        let store = MemoryLogStore()
        let model: RadioViewModel

        @MainActor
        init(settings: MemorySettingsStore = MemorySettingsStore(AppSettings())) {
            model = RadioViewModel(
                makeController: { _, _ in RadioController(transport: ScriptedTransport()) },
                serialDevices: { [] },
                settings: settings,
                diagnostics: DiagnosticLog(store: store, now: { 1_000 }),
                now: { 1_000 }
            )
        }
    }

    @Test("what the radio refuses is logged with its reason")
    func refusals() async {
        let setup = SilentSetup()
        setup.model.callsign = "N0CALL"
        await setup.model.connect()
        await setup.model.tune(to: ChannelMemory(name: "Private name", frequency: 146.52))
        await setup.model.toggleScan()
        #expect(setup.store.read().contains("Tuning refused: notReady"))
        #expect(setup.store.read().contains("Scan refused: notReady"))
        #expect(!setup.store.read().contains("Private name"))
        await setup.model.disconnect()
        #expect(setup.store.read().contains("RX audio so far: 0 underruns, 0 dropped samples"))
    }

    @Test("stored settings that cannot be read are logged, and the start says how the app is set up")
    func unreadableSettings() {
        let setup = SilentSetup(settings: MemorySettingsStore(data: Data("not JSON".utf8)))
        #expect(setup.store.read().contains("ERROR storage: The settings could not be read"))
        #expect(setup.store.read().contains("INFO app: Settings: connection"))
        #expect(!AppSettings.isUnreadable(nil))
        #expect(!SilentSetup().store.read().contains("could not be read"))
    }

    @Test("what the user types stays out of the log")
    func typedText() async {
        let setup = Setup()
        setup.model.selectedConnection = .simulator
        await setup.model.connect()
        #expect(await setup.waits(for: "Status: ready"))
        #expect(await KV4PTestSupport.eventually { setup.model.isReady })
        setup.model.frequencyText = "Private text"
        await setup.model.applyFrequency()
        #expect(setup.model.message?.contains("Private text") == true)
        #expect(!setup.text.contains("Private text"))
        #expect(setup.text.contains("An entered frequency was not valid"))
    }

    @Test("tuning, transmitting and what the radio reports are logged with their frequency")
    func tuning() async {
        let setup = Setup()
        setup.model.selectedConnection = .simulator
        setup.model.callsign = "N0CALL"
        await setup.model.connect()
        #expect(await KV4PTestSupport.eventually { setup.model.isReady })
        setup.model.frequencyText = "146.52"
        await setup.model.applyFrequency()
        #expect(await setup.waits(for: "Tuned: RX 146.5200 MHz, TX 146.5200 MHz"))
        #expect(await KV4PTestSupport.eventually { setup.model.canTransmit && setup.model.snapshot.isInSync })
        await setup.model.pressPTT()
        #expect(await setup.waits(for: "Transmit requested on 146.5200 MHz"))
        await setup.model.releasePTT()
        #expect(await setup.waits(for: "Transmit ended"))
    }

    @Test("PTT that is refused says why")
    func refusedPTT() async {
        let setup = Setup(microphone: FakeMicrophone(fails: true))
        setup.model.selectedConnection = .simulator
        setup.model.callsign = "N0CALL"
        await setup.model.connect()
        #expect(await KV4PTestSupport.eventually { setup.model.isReady })
        setup.model.frequencyText = "146.52"
        await setup.model.applyFrequency()
        #expect(await KV4PTestSupport.eventually { setup.model.canTransmit && setup.model.snapshot.isInSync })
        await setup.model.pressPTT()
        #expect(setup.text.contains("PTT refused: microphoneUnavailable"))
    }

    @Test("a radio that does not take the settings for a while is logged")
    func outOfSync() async {
        let store = MemoryLogStore()
        let time = TestTime()
        let transport = ScriptedTransport()
        let model = RadioViewModel(
            makeController: { _, _ in RadioController(transport: transport) },
            serialDevices: { [] },
            diagnostics: DiagnosticLog(store: store, now: { time.ms }),
            now: { time.ms },
            aprsTickInterval: .milliseconds(1)
        )
        await model.connect()
        var simulator = RadioSimulator(scenario: .ble)
        transport.streams.deliver(simulator.connect(at: .zero))
        #expect(await KV4PTestSupport.eventually { model.isReady })
        #expect(!store.read().contains("not taken the settings"))
        #expect(
            await KV4PTestSupport.eventually {
                time.advance(by: 1_000)
                return store.read().contains("not taken the settings for a while")
            }
        )
        transport.streams.publish(.failed(.connectionLost))
        #expect(await KV4PTestSupport.eventually { store.read().contains("No longer waiting for the radio") })
        await model.disconnect()
    }

    @Test("gaps in the sound are logged each minute, only when there are new ones")
    func rxAudio() async {
        let setup = Setup()
        setup.model.selectedConnection = .simulator
        await setup.model.connect()
        let block = ImaAdpcm.encodeBlock([Int16](repeating: 0, count: KV4P.audioBlockSamples))
        for _ in 0..<2_000 {
            setup.model.rxAudio.receive(block: block)
        }
        #expect(
            await KV4PTestSupport.eventually {
                setup.time.advance(by: 60_000)
                return setup.text.contains("RX audio so far: 0 underruns, ")
                    && !setup.text.contains(", 0 dropped samples")
            }
        )
    }

    @Test("a setting from iCloud that cannot be read is logged by its name only")
    func unreadableSyncedSetting() {
        let synced = MemorySyncedSettings()
        synced.set(["callsign": Data("not JSON".utf8)])
        let store = MemoryLogStore()
        _ = RadioViewModel(
            makeController: { _, _ in RadioController(transport: ScriptedTransport()) },
            serialDevices: { [] },
            settings: MemorySettingsStore(AppSettings()),
            syncedSettings: synced,
            diagnostics: DiagnosticLog(store: store, now: { 0 }),
            settingsSyncSleep: { _ in }
        )
        #expect(store.read().contains("A setting from iCloud could not be read: callsign"))
        #expect(!store.read().contains("not JSON"))
    }

    @Test("why a packet did not go out is logged once, until the reason changes")
    func blockedPackets() async {
        let setup = SilentSetup()
        setup.model.callsign = "N0CALL"
        setup.model.sendAPRSMessage(to: "N1CALL", text: "One")
        setup.model.sendAPRSMessage(to: "N1CALL", text: "Two")
        #expect(setup.store.read().contains("A packet did not go out"))
        #expect(!setup.store.read().contains("One"))

    }

    @Test("a packet the iGate cannot pass on is logged, with no link or if the link does not take it")
    func gate() async throws {
        for (link, callsign, reason) in [
            (nil, "N0CALL", "no internet link or callsign"),
            (FakeLink(), "N1CALL", "the internet link did not take it"),
        ] as [(FakeLink?, String, String)] {
            let store = MemoryLogStore()
            let simulator = Box<SimulatorTransport<ManualClock>>()
            let model = RadioViewModel(
                makeController: { _, rxAudio in
                    let clock = ManualClock()
                    let transport = SimulatorTransport(simulator: RadioSimulator(scenario: .ble), clock: clock)
                    simulator.value = transport
                    return RadioController(transport: transport, clock: clock, rxAudio: rxAudio)
                },
                serialDevices: { [] },
                internet: link,
                diagnostics: DiagnosticLog(store: store, now: { 0 })
            )
            await model.connect()
            #expect(await KV4PTestSupport.eventually { model.isReady })
            model.callsign = callsign
            model.isIGateEnabled = true
            let packet = try APRSParser.parse(tnc2: "N2CALL>APRS,WIDE1-1:>gate me")
            await simulator.value?.hear(try packet.ax25Frame())
            #expect(await KV4PTestSupport.eventually { store.read().contains(reason) })
            #expect(!store.read().contains("gate me"))
            await model.disconnect()
        }
    }

    @Test("a connection is told by its kind, not by the name of the port or radio")
    func connectionKinds() {
        #expect(RadioViewModel.kind(of: .serial("/dev/cu.usbserial-0001")) == "USB")
        #expect(RadioViewModel.kind(of: .bluetooth) == "Bluetooth")
        #expect(RadioViewModel.kind(of: .simulator) == "simulator")
    }

    @Test("the app going away and coming back is logged once each")
    func lifecycle() {
        let setup = Setup()
        setup.model.isAppActive = true
        #expect(!setup.text.contains("In the foreground"))
        setup.model.isAppActive = false
        setup.model.isAppActive = true
        #expect(setup.text.contains("In the background"))
        #expect(setup.text.contains("In the foreground"))
    }

    @Test("an allowed permission is logged once")
    func allowed() {
        let setup = Setup()
        setup.permissions.setQuietly(.location, .granted)
        setup.model.refreshPermissions()
        setup.model.refreshPermissions()
        let lines = setup.text.components(separatedBy: "\n").filter { $0.contains("permissions: Allowed: location") }
        #expect(lines.count == 1)
    }
}

/// What the controller logs about the connection (ADR-0059).
@Suite("Diagnostics in the controller")
struct DiagnosticsControllerTests {
    private static func log() -> (MemoryLogStore, DiagnosticLog) {
        let store = MemoryLogStore()
        return (store, DiagnosticLog(store: store, now: { 0 }))
    }

    @Test("a transmission that reaches its limit says so")
    func runaway() async throws {
        let (store, log) = Self.log()
        var setup = TransmitControllerTests.Scripted(microphone: FakeMicrophone(), diagnostics: log)
        try await setup.ready()
        try await setup.controller.startTransmitting()
        await setup.clock.waitForSleepers(1)
        setup.clock.advance(by: .seconds(180))
        #expect(await eventually { store.read().contains("reached its time limit") })
    }

    @Test("a microphone that does not start says why")
    func microphone() async throws {
        let (store, log) = Self.log()
        var setup = TransmitControllerTests.Scripted(microphone: FakeMicrophone(fails: true), diagnostics: log)
        try await setup.ready()
        await #expect(throws: RadioError.microphoneUnavailable) { try await setup.controller.startTransmitting() }
        #expect(store.read().contains("ERROR transmit: Microphone:"))
    }

    @Test("unreadable frames are counted, without flooding the log")
    func unreadableFrames() async throws {
        let (store, log) = Self.log()
        var setup = TransmitControllerTests.Scripted(microphone: FakeMicrophone(), diagnostics: log)
        try await setup.ready()
        for _ in 0..<50 {
            setup.transport.streams.deliver(KV4P.vendorFrame(DeviceCommand.deviceState.rawValue, [1]))
            setup.transport.streams.deliver(KV4P.vendorFrame(DeviceCommand.windowUpdate.rawValue, [1]))
        }
        #expect(await eventually { store.read().contains("100 in this session") })
        #expect(store.read().contains("Unreadable device state, 1 in this session"))
        #expect(store.read().components(separatedBy: "Unreadable").count == 3)
    }

    @Test("a failed send is logged once")
    func sendFails() async throws {
        let (store, log) = Self.log()
        let transport = ScriptedTransport(failsToSend: true)
        let controller = RadioController(transport: transport, clock: ManualClock(), diagnostics: log)
        await controller.connect()
        var simulator = RadioSimulator(scenario: .ble)
        transport.streams.deliver(simulator.connect(at: .zero))
        #expect(await eventually { store.read().contains("Sending failed: connectionLost") })
        #expect(await eventually { await controller.snapshot.status == .ready })
        await controller.update { $0.setSquelch(3) }
        await controller.update { $0.setSquelch(4) }
        await Task.yield()
        #expect(store.read().components(separatedBy: "Sending failed").count == 2)
    }

    @Test("a radio that leaves no room for a while is logged, and when it has room again")
    func stall() async throws {
        let (store, log) = Self.log()
        var setup = TransmitControllerTests.Scripted(microphone: FakeMicrophone(), diagnostics: log)
        var scenario = Scenario.ble
        scenario.windowSize = 1
        setup.simulator = RadioSimulator(scenario: scenario)
        await setup.controller.connect()
        setup.transport.streams.deliver(setup.simulator.connect(at: .zero))
        let clock = setup.clock
        #expect(
            await eventually {
                clock.advance(by: .seconds(1))
                return store.read().contains("left no room to send")
            }
        )
        setup.transport.streams.deliver(DeviceFrameEncoder.windowUpdate(WindowUpdate(size: 100_000)))
        #expect(await eventually { store.read().contains("has room to send again") })
    }

    @Test("a packet the radio refuses says why")
    func refusedPacket() async {
        let (store, log) = Self.log()
        let controller = RadioController(transport: ScriptedTransport(), clock: ManualClock(), diagnostics: log)
        await #expect(throws: RadioError.notReady) { try await controller.transmitAX25([1], frequency: 144.8) }
        #expect(store.read().contains("Sending a packet failed: notReady"))
    }

    @Test("with details on, the traffic of each minute is summed up")
    func traffic() async throws {
        let (store, log) = Self.log()
        log.detailedUntilMs = 1
        var setup = TransmitControllerTests.Scripted(microphone: FakeMicrophone(), diagnostics: log)
        try await setup.ready()
        setup.clock.advance(by: .seconds(30))
        setup.transport.streams.deliver(DeviceFrameEncoder.windowUpdate(WindowUpdate(size: 10)))
        setup.clock.advance(by: .seconds(30))
        setup.transport.streams.deliver(DeviceFrameEncoder.windowUpdate(WindowUpdate(size: 10)))
        #expect(await eventually { store.read().contains("DETAIL connection: Traffic in the last minute: in ") })
    }
}
