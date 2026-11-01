import KV4PAPRS
import KV4PSimulator
import KV4PTestSupport
import Synchronization
import Testing

@testable import KV4PRadio

/// A location the test sets.
final class FakeLocation: LocationProvider {
    private let point = Mutex<GeoPoint?>(GeoPoint(latitude: 49.058_33, longitude: -72.029_17))

    func set(_ value: GeoPoint?) {
        point.withLock { $0 = value }
    }

    func currentLocation() async -> GeoPoint? {
        point.withLock { $0 }
    }
}

/// Position beacons and digipeating of the radio screen (`RadioAudioService.sendPositionBeacon`).
@MainActor
@Suite("Radio view model beacons")
struct RadioViewModelBeaconTests {
    @MainActor
    final class Setup {
        let simulator = Box<SimulatorTransport<ManualClock>>()
        let time = TestTime()
        let location = FakeLocation()
        let model: RadioViewModel

        init() {
            let simulator = simulator
            let time = time
            model = RadioViewModel(
                makeController: { _, rxAudio in
                    let clock = ManualClock()
                    let transport = SimulatorTransport(simulator: RadioSimulator(scenario: .ble), clock: clock)
                    simulator.value = transport
                    return RadioController(transport: transport, clock: clock, rxAudio: rxAudio)
                },
                serialDevices: { [] },
                location: location,
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

        var sent: [APRSPacket] {
            get async {
                await (simulator.value?.simulator.transmittedPackets ?? []).compactMap {
                    try? APRSParser.parse(ax25: $0.packet)
                }
            }
        }
    }

    @Test("beacons go out at once and every five minutes, compressed with the chosen symbol")
    func beacons() async {
        let setup = Setup()
        await setup.connect()
        #expect(setup.model.beaconSymbol == .phone)
        setup.model.beaconSymbol = .car
        setup.model.isBeaconEnabled = true
        #expect(await eventually { await setup.sent.count == 1 })
        let beacon = await setup.sent.first
        #expect(beacon?.info.position?.source == "Compressed")
        #expect(beacon?.info.position?.position.symbolCode == UInt16(UInt8(ascii: ">")))
        #expect(beacon?.dti == UInt8(ascii: "="))
        #expect(setup.model.aprsEvents.first?.fromCallsign == "N0CALL")
        setup.time.advance(by: 299_999)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await setup.sent.count == 1)
        setup.time.advance(by: 1)
        #expect(await eventually { await setup.sent.count == 2 })
        setup.model.isBeaconEnabled = false
        setup.time.advance(by: 300_000)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await setup.sent.count == 2)
    }

    @Test("an approximate position is rounded to two decimals")
    func approximate() async {
        let setup = Setup()
        await setup.connect()
        setup.model.isBeaconApproximate = true
        setup.model.isBeaconEnabled = true
        #expect(await eventually { await setup.sent.count == 1 })
        let position = await setup.sent.first?.info.position?.position
        #expect(abs((position?.latitude ?? 0) - 49.06) < 0.000_1)
        #expect(abs((position?.longitude ?? 0) + 72.03) < 0.000_1)
    }

    @Test("without a location no beacon is sent and the user is told")
    func noLocation() async {
        let setup = Setup()
        await setup.connect()
        setup.location.set(nil)
        setup.model.isBeaconEnabled = true
        #expect(await RadioViewModelTests.eventually(setup.model) { $0.message == "Your location is unknown." })
        #expect(await setup.sent.isEmpty)
    }

    @Test("without a location provider beacons cannot be enabled")
    func noProvider() async {
        let model = RadioViewModelTests.model()
        #expect(!model.canBeacon)
    }

    @Test("digipeating repeats WIDE1-1 packets")
    func digipeating() async throws {
        let setup = Setup()
        await setup.connect()
        #expect(!setup.model.isDigipeatingEnabled)
        setup.model.isDigipeatingEnabled = true
        #expect(setup.model.isDigipeatingEnabled)
        let packet = try APRSParser.parse(tnc2: "N1CALL>APRS,WIDE1-1,WIDE2-1:>hello")
        await setup.simulator.value?.hear(try packet.ax25Frame())
        #expect(await eventually { await setup.sent.first?.digipeaters.first?.description == "N0CALL*" })
    }
}
