import KV4PAPRS
import KV4PSimulator
import KV4PTestSupport
import Synchronization
import Testing

@testable import KV4PRadio

/// An APRS-IS connection the test controls.
final class FakeLink: APRSInternetLink {
    let received: AsyncStream<String>
    let delivered: AsyncStream<APRSInternetRequest>
    let receive: AsyncStream<String>.Continuation
    let deliver: AsyncStream<APRSInternetRequest>.Continuation
    private let state = Mutex<(settings: [APRSISSettings], sent: [APRSInternetRequest])>(([], []))

    init() {
        (received, receive) = AsyncStream.makeStream()
        (delivered, deliver) = AsyncStream.makeStream()
    }

    var isLoggedIn: Bool { settings.last?.isEnabled == true }
    var settings: [APRSISSettings] { state.withLock { $0.settings } }
    var sent: [APRSInternetRequest] { state.withLock { $0.sent } }

    func update(_ settings: APRSISSettings) {
        state.withLock { $0.settings.append(settings) }
    }

    func send(_ request: APRSInternetRequest, as callsign: String) -> Bool {
        state.withLock { $0.sent.append(request) }
        return callsign == "N0CALL"
    }
}

/// iGate and the APRS-IS feed of the radio screen (`RadioAudioService.updateAprsIsConnection`).
@MainActor
@Suite("Radio view model APRS-IS")
struct RadioViewModelInternetTests {
    @MainActor
    final class Setup {
        let simulator = Box<SimulatorTransport<ManualClock>>()
        let time = TestTime()
        let link = FakeLink()
        let location = FakeLocation()
        let model: RadioViewModel

        init(location: Bool = true) {
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
                location: location ? self.location : nil,
                internet: link,
                now: { time.ms },
                aprsTickInterval: .milliseconds(5)
            )
        }
    }

    @Test("the connection is off until iGate or the APRS-IS feed is on")
    func settings() async {
        let setup = Setup()
        #expect(setup.model.canUseInternet)
        setup.model.callsign = "N0CALL"
        #expect(setup.link.settings.last?.isEnabled == false)
        setup.model.isIGateEnabled = true
        #expect(setup.link.settings.last?.isTransmitEnabled == true)
        #expect(setup.link.settings.last?.isReceiveEnabled == false)
        #expect(setup.link.settings.last?.callsign == "N0CALL")
        setup.model.isInternetFeedEnabled = true
        #expect(
            await RadioViewModelTests.eventually(setup.model) { _ in setup.link.settings.last?.latitude == 49.058_33 }
        )
        #expect(setup.link.settings.last?.isReceiveEnabled == true)
        #expect(setup.model.isInternetConnected)
        setup.model.isIGateEnabled = false
        setup.model.isInternetFeedEnabled = false
        #expect(setup.link.settings.last?.isEnabled == false)
        #expect(setup.link.settings.last?.latitude == nil)
    }

    @Test("APRS-IS packets join the feed; confirmed lines are recorded")
    func feed() async throws {
        let setup = Setup()
        setup.link.receive.yield("N1CALL>APRS,TCPIP*:>from the internet")
        #expect(await RadioViewModelTests.eventually(setup.model) { $0.aprsEvents.first?.isInternetOnly == true })
        setup.link.deliver.yield(APRSInternetRequest(line: "N1CALL>APRS,TCPIP*,qAO,N0CALL:>x", eventId: 1))
        #expect(await RadioViewModelTests.eventually(setup.model) { $0.aprsEvents.first?.packetCount == 2 })
    }

    @Test("with the iGate on, received RF packets go to APRS-IS")
    func gate() async throws {
        let setup = Setup()
        await setup.model.connect()
        #expect(await RadioViewModelTests.eventually(setup.model) { $0.isReady })
        setup.model.callsign = "N0CALL"
        setup.model.isIGateEnabled = true
        let packet = try APRSParser.parse(tnc2: "N1CALL>APRS,WIDE1-1:>gate me")
        await setup.simulator.value?.hear(try packet.ax25Frame())
        #expect(await eventually { setup.link.sent.first?.line == "N1CALL>APRS,WIDE1-1,qAO,N0CALL:>gate me" })
        setup.model.frequencyText = "144.8"
        await setup.model.applyFrequency()
        #expect(await RadioViewModelTests.eventually(setup.model) { $0.canTransmit && $0.snapshot.isInSync })
        setup.model.sendAPRSMessage(to: "N1CALL", text: "hi")
        #expect(await eventually { setup.link.sent.count == 2 })
        #expect(setup.link.sent.last?.line.hasPrefix("N0CALL>APKVPA,TCPIP*::N1CALL   :hi{") == true)
        setup.model.isBeaconEnabled = true
        #expect(await eventually { setup.link.sent.count == 3 })
    }

    @Test("without a location the APRS-IS feed uses the server's own filter; without a link nothing happens")
    func noLocation() async {
        let setup = Setup(location: false)
        setup.model.callsign = "N0CALL"
        setup.model.isInternetFeedEnabled = true
        #expect(setup.link.settings.last?.isReceiveEnabled == true)
        #expect(setup.link.settings.last?.latitude == nil)
        let plain = RadioViewModelTests.model()
        #expect(!plain.canUseInternet)
        plain.isIGateEnabled = true
        #expect(!plain.isInternetConnected)
    }
}
