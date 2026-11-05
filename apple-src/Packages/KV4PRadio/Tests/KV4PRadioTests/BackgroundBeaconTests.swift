import KV4PAPRS
import KV4PSimulator
import KV4PTestSupport
import Testing

@testable import KV4PProtocol
@testable import KV4PRadio

/// Position beacons with the screen locked, and how often they go out (ADR-0056).
@MainActor
@Suite("Background beacons")
struct BackgroundBeaconTests {
    final class FakeBackgroundLocation: BackgroundLocationKeeping {
        private(set) var starts = 0
        private(set) var stops = 0
        var isRunning: Bool { starts > stops }

        func start() {
            starts += 1
        }

        func stop() {
            stops += 1
        }
    }

    @MainActor
    final class Setup {
        let simulator = Box<SimulatorTransport<ManualClock>>()
        let time = TestTime()
        let location = FakeLocation()
        let session = FakeBackgroundLocation()
        let alerts = FakeFailureAlerts(usesDialog: false)
        let permissions = FakePermissions()
        let store = MemorySettingsStore()
        let model: RadioViewModel

        init(hasBackgroundLimit: Bool = true) {
            let simulator = simulator
            let time = time
            location.set(GeoPoint(latitude: 49, longitude: -72))
            model = RadioViewModel(
                makeController: { _, rxAudio in
                    let clock = ManualClock()
                    let transport = SimulatorTransport(simulator: RadioSimulator(scenario: .ble), clock: clock)
                    simulator.value = transport
                    return RadioController(transport: transport, clock: clock, rxAudio: rxAudio)
                },
                serialDevices: { [] },
                location: location,
                backgroundLocation: hasBackgroundLimit ? session : nil,
                settings: store,
                failureAlerts: alerts,
                permissions: permissions,
                now: { time.ms },
                aprsTickInterval: .milliseconds(5)
            )
        }

        func connect() async {
            await model.connect()
            #expect(await RadioViewModelTests.eventually(model) { $0.isReady && $0.snapshot.isInSync })
            model.frequencyText = "144.8"
            await model.applyFrequency()
            #expect(await RadioViewModelTests.eventually(model) { $0.canTransmit && $0.snapshot.isInSync })
            model.callsign = "N0CALL"
        }

        var sentCount: Int {
            get async {
                await (simulator.value?.simulator.transmittedPackets ?? []).count
            }
        }

        func waitForBeacons(_ count: Int) async -> Bool {
            for _ in 0..<500 {
                if await sentCount >= count { return true }
                try? await Task.sleep(for: .milliseconds(2))
            }
            return false
        }

        /// A while in which a beacon would have gone out, if one was due.
        func settle() async {
            try? await Task.sleep(for: .milliseconds(60))
        }
    }

    @Test("the session runs only with the beacon on, a radio and everything allowed")
    func sessionConditions() async {
        let setup = Setup()
        #expect(!setup.session.isRunning)
        setup.model.isBeaconEnabled = true
        #expect(!setup.session.isRunning)
        await setup.connect()
        #expect(await KV4PTestSupport.eventually { setup.session.isRunning })

        setup.model.isBeaconEnabled = false
        #expect(!setup.session.isRunning)
        setup.model.isBeaconEnabled = true
        #expect(setup.session.isRunning)

        setup.model.isListenOnly = true
        #expect(!setup.session.isRunning)
        setup.model.isListenOnly = false
        #expect(setup.session.isRunning)

        setup.model.callsign = ""
        #expect(!setup.session.isRunning)
        setup.model.callsign = "N0CALL"
        #expect(setup.session.isRunning)

        setup.model.isBackgroundBeaconEnabled = false
        #expect(!setup.session.isRunning)
        setup.model.isBackgroundBeaconEnabled = true
        #expect(setup.session.isRunning)

        await setup.model.disconnect()
        #expect(!setup.session.isRunning)
    }

    @Test("access denied ends the beacon and the session, and says so")
    func denied() async {
        let setup = Setup()
        await setup.connect()
        setup.model.isBeaconEnabled = true
        #expect(setup.session.isRunning)
        setup.permissions.set(.location, .denied)
        #expect(await KV4PTestSupport.eventually { !setup.model.isBeaconEnabled })
        #expect(!setup.session.isRunning)
        #expect(setup.alerts.delivered == [Permission.location.deniedMessage])
    }

    @Test("access denied without a beacon stays quiet")
    func deniedWithoutBeacon() async {
        let setup = Setup()
        setup.permissions.set(.location, .denied)
        #expect(await KV4PTestSupport.eventually { setup.model.isDenied(.location) })
        #expect(setup.alerts.delivered.isEmpty)
    }

    @Test("a session cannot start in the background, so it starts on the way back")
    func startsInForeground() async {
        let setup = Setup()
        await setup.connect()
        setup.model.isAppActive = false
        setup.model.isBeaconEnabled = true
        await setup.settle()
        #expect(!setup.session.isRunning)
        setup.model.isAppActive = true
        #expect(setup.session.isRunning)
    }

    @Test("a running session stays in the background")
    func staysInBackground() async {
        let setup = Setup()
        await setup.connect()
        setup.model.isBeaconEnabled = true
        #expect(setup.session.isRunning)
        setup.model.isAppActive = false
        await setup.settle()
        #expect(setup.session.isRunning)
        #expect(setup.session.starts == 1)
    }

    @Test("with the session, beacons go on in the background")
    func beaconsInBackground() async {
        let setup = Setup()
        await setup.connect()
        setup.model.isBeaconEnabled = true
        #expect(await setup.waitForBeacons(1))
        setup.model.isAppActive = false
        setup.time.advance(by: RadioViewModel.beaconIntervalMs)
        #expect(await setup.waitForBeacons(2))
    }

    @Test("switched off, beacons wait for the app and go out when it returns")
    func waitsWithoutSwitch() async {
        let setup = Setup()
        await setup.connect()
        setup.model.isBackgroundBeaconEnabled = false
        setup.model.isBeaconEnabled = true
        #expect(await setup.waitForBeacons(1))
        setup.model.isAppActive = false
        setup.time.advance(by: RadioViewModel.beaconIntervalMs)
        await setup.settle()
        #expect(await setup.sentCount == 1)
        setup.model.isAppActive = true
        #expect(await setup.waitForBeacons(2))
    }

    @Test("a platform without the limit needs no session, and the switch is not offered")
    func noLimit() async {
        let setup = Setup(hasBackgroundLimit: false)
        #expect(!setup.model.supportsBackgroundBeacon)
        #expect(Setup().model.supportsBackgroundBeacon)
        await setup.connect()
        setup.model.isBeaconEnabled = true
        #expect(await setup.waitForBeacons(1))
        setup.model.isAppActive = false
        setup.time.advance(by: RadioViewModel.beaconIntervalMs)
        #expect(await setup.waitForBeacons(2))
    }

    @Test("the interval decides when the next beacon goes out")
    func interval() async {
        let setup = Setup()
        #expect(setup.model.beaconIntervalMinutes == 5)
        #expect(AppSettings.beaconIntervalOptions == [2, 5, 10, 15, 30, 60])
        await setup.connect()
        setup.model.beaconIntervalMinutes = 10
        setup.model.isBeaconEnabled = true
        #expect(await setup.waitForBeacons(1))
        setup.time.advance(by: 9 * 60_000)
        await setup.settle()
        #expect(await setup.sentCount == 1)
        setup.time.advance(by: 60_000)
        #expect(await setup.waitForBeacons(2))
    }

    @Test("a shorter interval counts from now, not after the long wait")
    func shorterInterval() async {
        let setup = Setup()
        await setup.connect()
        setup.model.beaconIntervalMinutes = 60
        setup.model.isBeaconEnabled = true
        #expect(await setup.waitForBeacons(1))
        setup.model.beaconIntervalMinutes = 2
        setup.time.advance(by: 2 * 60_000)
        #expect(await setup.waitForBeacons(2))
    }

    @Test("a position that cannot be found is reported once, until a beacon has worked again")
    func failureOnce() async {
        let setup = Setup()
        await setup.connect()
        setup.location.set(nil)
        setup.model.isBeaconEnabled = true
        #expect(await KV4PTestSupport.eventually { setup.alerts.delivered.count == 1 })
        #expect(setup.model.message == "Your location is unknown.")
        setup.time.advance(by: RadioViewModel.beaconIntervalMs)
        await setup.settle()
        #expect(setup.alerts.delivered.count == 1)
        setup.location.set(GeoPoint(latitude: 49, longitude: -72))
        setup.time.advance(by: RadioViewModel.beaconIntervalMs)
        #expect(await setup.waitForBeacons(1))
        setup.location.set(nil)
        setup.time.advance(by: RadioViewModel.beaconIntervalMs)
        #expect(await KV4PTestSupport.eventually { setup.alerts.delivered.count == 2 })
    }

    @Test("the settings are kept: the switch on this device, the interval also for others")
    func settings() throws {
        let setup = Setup()
        #expect(setup.model.isBackgroundBeaconEnabled)
        setup.model.isBackgroundBeaconEnabled = false
        setup.model.beaconIntervalMinutes = 15
        #expect(!setup.store.settings.isBackgroundBeaconEnabled)
        #expect(setup.store.settings.beaconIntervalMinutes == 15)
        let keys = SettingsSync.values(of: AppSettings()).keys
        #expect(keys.contains("beaconIntervalMinutes"))
        #expect(!keys.contains("isBackgroundBeaconEnabled"))
    }

    @Test("stored settings come back")
    func restored() throws {
        var stored = AppSettings()
        stored.isBackgroundBeaconEnabled = false
        stored.beaconIntervalMinutes = 30
        let restored = RadioViewModel(
            makeController: { _, _ in RadioController(transport: ScriptedTransport()) },
            serialDevices: { [] },
            settings: MemorySettingsStore(stored)
        )
        #expect(!restored.isBackgroundBeaconEnabled)
        #expect(restored.beaconIntervalMinutes == 30)
    }
}
