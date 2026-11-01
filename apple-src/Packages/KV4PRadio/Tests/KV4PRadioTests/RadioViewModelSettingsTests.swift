import Foundation
import KV4PAPRS
import KV4PAudio
import KV4PPersistence
import KV4PSimulator
import KV4PTestSupport
import Synchronization
import Testing

@testable import KV4PRadio

/// A settings store in memory.
final class MemorySettingsStore: SettingsStore {
    private let stored = Mutex<Data?>(nil)

    init(_ settings: AppSettings? = nil) {
        stored.withLock { $0 = settings?.data }
    }

    var settings: AppSettings { AppSettings(data: load()) }

    func load() -> Data? {
        stored.withLock { $0 }
    }

    func save(_ data: Data) {
        stored.withLock { $0 = data }
    }
}

/// `MainActivity.applySettings…` and `SettingsActivity`: the app settings are kept between launches.
@MainActor
@Suite("Radio view model settings")
struct RadioViewModelSettingsTests {
    static func model(
        _ store: MemorySettingsStore,
        simulator: Box<SimulatorTransport<ManualClock>> = Box(),
        location: FakeLocation? = nil,
        time: TestTime = TestTime()
    ) -> RadioViewModel {
        RadioViewModel(
            makeController: { _, rxAudio in
                let clock = ManualClock()
                let transport = SimulatorTransport(simulator: RadioSimulator(scenario: .ble), clock: clock)
                simulator.value = transport
                return RadioController(transport: transport, clock: clock, rxAudio: rxAudio)
            },
            serialDevices: { [] },
            location: location,
            settings: store,
            now: { time.ms },
            aprsTickInterval: .milliseconds(5)
        )
    }

    @Test("stored settings are restored at launch")
    func restore() {
        var settings = AppSettings()
        settings.callsign = "n0call"
        settings.micGain = .high
        settings.isStickyPTT = true
        settings.isBeaconEnabled = true
        settings.beaconSymbol = .car
        settings.isBeaconApproximate = true
        settings.beaconFrequency = 144.39
        settings.isDigipeatingEnabled = true
        settings.aprsDestinationFilter = .mine
        settings.txLimits.max2m = 146
        settings.selectedGroup = "Repeaters"
        let model = Self.model(MemorySettingsStore(settings))
        #expect(model.callsign == "N0CALL")
        #expect(model.micGain == .high)
        #expect(model.isStickyPTT)
        #expect(model.isBeaconEnabled)
        #expect(model.beaconSymbol == .car)
        #expect(model.isBeaconApproximate)
        #expect(model.beaconFrequency == 144.39)
        #expect(model.isDigipeatingEnabled)
        #expect(model.aprsDestinationFilter == .mine)
        #expect(model.txLimits.max2m == 146)
        #expect(model.selectedGroup == "Repeaters")
    }

    @Test("every change is saved")
    func save() {
        let store = MemorySettingsStore()
        let model = Self.model(store)
        model.callsign = "N0CALL"
        model.micGain = .low
        model.isStickyPTT = true
        model.beaconSymbol = .house
        model.isBeaconApproximate = true
        model.beaconFrequency = 145.175
        model.isDigipeatingEnabled = true
        model.isIGateEnabled = true
        model.isInternetFeedEnabled = true
        model.aprsDestinationFilter = .mine
        model.txLimits.min70cm = 430
        model.selectedGroup = "Local"
        model.isBeaconEnabled = true
        let saved = store.settings
        #expect(saved == model.settings)
        #expect(saved.callsign == "N0CALL")
        #expect(saved.isIGateEnabled && saved.isInternetFeedEnabled && saved.isBeaconEnabled)
        #expect(saved.txLimits.min70cm == 430)
    }

    @Test("the TX limits apply to the radio, also when they change while connected")
    func txLimits() async {
        var settings = AppSettings()
        settings.txLimits.max2m = 147
        let model = Self.model(MemorySettingsStore(settings))
        await model.connect()
        #expect(await RadioViewModelTests.eventually(model) { $0.isReady && $0.snapshot.isInSync })
        model.frequencyText = "147.5"
        await model.applyFrequency()
        #expect(await RadioViewModelTests.eventually(model) { $0.snapshot.isInSync && $0.frequencyText == "147.5000" })
        #expect(!model.canTransmit)
        model.txLimits.max2m = 148
        #expect(await RadioViewModelTests.eventually(model) { $0.canTransmit })
    }

    @Test("beacons go out on the beacon frequency, or on the current one")
    func beaconFrequency() async {
        let simulator = Box<SimulatorTransport<ManualClock>>()
        let time = TestTime()
        let model = Self.model(MemorySettingsStore(), simulator: simulator, location: FakeLocation(), time: time)
        await model.connect()
        #expect(await RadioViewModelTests.eventually(model) { $0.isReady && $0.snapshot.isInSync })
        model.frequencyText = "146.52"
        await model.applyFrequency()
        #expect(await RadioViewModelTests.eventually(model) { $0.canTransmit && $0.snapshot.isInSync })
        model.callsign = "N0CALL"
        model.beaconFrequency = 144.39
        model.isBeaconEnabled = true
        #expect(await eventually { await simulator.value?.simulator.transmittedPackets.count == 1 })
        #expect(await simulator.value?.simulator.transmittedPackets.first?.channel?.freqTx == 144.39)
        model.beaconFrequency = nil
        time.advance(by: RadioViewModel.beaconIntervalMs)
        #expect(await eventually { await simulator.value?.simulator.transmittedPackets.count == 2 })
        #expect(await simulator.value?.simulator.transmittedPackets.last?.channel?.freqTx == 146.52)
    }

    @Test("only mine: messages between other stations are hidden, everything else stays")
    func destinationFilter() async throws {
        let simulator = Box<SimulatorTransport<ManualClock>>()
        let model = Self.model(MemorySettingsStore(), simulator: simulator)
        model.callsign = "N0CALL"
        await model.connect()
        #expect(await RadioViewModelTests.eventually(model) { $0.isReady })
        for (destination, text) in [("N2CALL", "elsewhere"), ("N0CALL", "for me")] {
            let payload = Array(":\(destination.padding(toLength: 9, withPad: " ", startingAt: 0)):\(text)".utf8)
            let packet = APRSPacket(source: "N1CALL", destination: "APRS", digipeaters: [], payload: payload)
            await simulator.value?.hear(try packet.ax25Frame())
        }
        let position = try #require(RadioViewModelAPRSTests.position)
        await simulator.value?.hear(position)
        #expect(await RadioViewModelTests.eventually(model) { $0.aprsEvents.count == 3 })
        model.aprsDestinationFilter = .mine
        #expect(model.aprsEvents.count == 2)
        #expect(!model.aprsEvents.contains { $0.body == "elsewhere" })
        model.aprsDestinationFilter = .all
        #expect(model.aprsEvents.count == 3)
    }
}
