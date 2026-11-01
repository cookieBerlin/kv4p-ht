import Foundation
import KV4PAPRS
import KV4PSimulator
import KV4PTestSupport
import Synchronization
import Testing

@testable import KV4PRadio

/// Milliseconds under test control.
final class TestTime: Sendable {
    private let value = Mutex<Int64>(1_000_000)

    var ms: Int64 { value.withLock { $0 } }

    func advance(by ms: Int64) {
        value.withLock { $0 += ms }
    }
}

/// The APRS feed of the radio screen.
@MainActor
@Suite("Radio view model APRS")
struct RadioViewModelAPRSTests {
    /// `N0CALL>APRS:!4903.50N/07201.75W-Test` (javAX25 vector).
    static let position = try? [UInt8](
        hex: "82a0a4a64040609c60868298986103f021343930332e35304e2f30373230312e3735572d54657374"
    )

    @Test("received packets become events, newest first; repeats count up")
    func feed() async throws {
        let simulator = Box<SimulatorTransport<ManualClock>>()
        let time = Mutex<Int64>(1_000)
        let model = RadioViewModel(
            makeController: { _, rxAudio in
                let clock = ManualClock()
                let transport = SimulatorTransport(simulator: RadioSimulator(scenario: .ble), clock: clock)
                simulator.value = transport
                return RadioController(transport: transport, clock: clock, rxAudio: rxAudio)
            },
            serialDevices: { [] },
            now: { time.withLock { $0 } }
        )
        await model.connect()
        #expect(await RadioViewModelTests.eventually(model) { $0.isReady })
        let position = try #require(Self.position)
        await simulator.value?.hear(position)
        #expect(await RadioViewModelTests.eventually(model) { $0.aprsEvents.count == 1 })
        #expect(model.aprsEvents.first?.comment == "Test")
        #expect(model.aprsEvents.first?.firstSeenMs == 1_000)
        time.withLock { $0 = 2_000 }
        await simulator.value?.hear(position)
        #expect(await RadioViewModelTests.eventually(model) { $0.aprsEvents.first?.packetCount == 2 })
        await simulator.value?.hear([0x01, 0x02])  // not an AX.25 frame
        time.withLock { $0 = 100_000 }
        await simulator.value?.hear(position)
        #expect(await RadioViewModelTests.eventually(model) { $0.aprsEvents.count == 2 })
        #expect(model.aprsEvents.map(\.id) == [2, 1])
    }

    @Test("events are stamped with the system time by default")
    func systemTime() {
        let before = Int64(Date().timeIntervalSince1970 * 1000)
        #expect((before...before + 60_000).contains(RadioViewModel.systemTimeMs()))
    }

    /// A connected model on 144.800 MHz with time under test control.
    @MainActor
    final class Messaging {
        let simulator = Box<SimulatorTransport<ManualClock>>()
        let time = TestTime()
        let microphone = FakeMicrophone()
        let model: RadioViewModel

        init() {
            let simulator = simulator
            let time = time
            let microphone = microphone
            model = RadioViewModel(
                makeController: { _, rxAudio in
                    let clock = ManualClock()
                    let transport = SimulatorTransport(simulator: RadioSimulator(scenario: .ble), clock: clock)
                    simulator.value = transport
                    return RadioController(transport: transport, clock: clock, rxAudio: rxAudio, microphone: microphone)
                },
                serialDevices: { [] },
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
        }

        var sent: [[UInt8]] {
            get async { await simulator.value?.simulator.transmittedPackets.map(\.packet) ?? [] }
        }

        func advance(by ms: Int64) {
            time.advance(by: ms)
        }

        func hear(_ tnc2: String) async throws {
            let packet = try APRSParser.parse(tnc2: tnc2)
            await simulator.value?.hear(try packet.ax25Frame())
        }
    }

    @Test("messages need a callsign")
    func noCallsign() async {
        let setup = Messaging()
        await setup.connect()
        setup.model.sendAPRSMessage(to: "N1CALL", text: "hi")
        #expect(setup.model.message == "Set your callsign to send APRS messages.")
        #expect(await setup.sent.isEmpty)
    }

    @Test("a message is sent on the TX frequency, retried until acknowledged")
    func sendRetryAcknowledge() async throws {
        let setup = Messaging()
        await setup.connect()
        setup.model.callsign = " n0call "
        #expect(setup.model.callsign == "N0CALL")
        setup.model.sendAPRSMessage(to: "n1call", text: "hi|there~{x")
        #expect(await eventually { await setup.sent.count == 1 })
        let message = try #require(setup.model.aprsEvents.first)
        #expect(message.body == "hi there  x")
        #expect(message.deliveryState == .pending)
        let channel = await setup.simulator.value?.simulator.transmittedPackets.first?.channel
        #expect(channel?.freqTx == 144.8)
        setup.advance(by: 15_000)
        #expect(await eventually { await setup.sent.count == 2 })
        let identifier = try #require(message.messageIdentifier)
        try await setup.hear("N1CALL>APRS::N0CALL   :ack\(identifier)")
        #expect(await RadioViewModelTests.eventually(setup.model) { $0.aprsEvents.first?.deliveryState == .delivered })
    }

    @Test("messages to us are acknowledged; without a recipient a message is a bulletin")
    func acknowledgeAndBulletin() async throws {
        let setup = Messaging()
        await setup.connect()
        setup.model.callsign = "N0CALL"
        try await setup.hear("N1CALL>APRS::N0CALL   :hello{7")
        #expect(await RadioViewModelTests.eventually(setup.model) { $0.aprsEvents.count == 1 })
        setup.advance(by: 1_000)
        #expect(await eventually { await setup.sent.count == 1 })
        let ack = try APRSParser.parse(ax25: try #require(await setup.sent.first))
        #expect(ack.info.message?.isAck == true)
        setup.model.sendAPRSMessage(to: " ", text: "to all")
        #expect(await eventually { await setup.sent.count == 2 })
        #expect(setup.model.aprsEvents.first?.toCallsign == "BLN1CQ")
    }

    @Test("nothing is sent while transmitting, or with a callsign AX.25 cannot carry")
    func notAccepted() async throws {
        let setup = Messaging()
        await setup.connect()
        setup.model.callsign = "N0CALL"
        await setup.model.pressPTT()
        setup.model.sendAPRSMessage(to: "N1CALL", text: "busy")
        #expect(setup.model.message == "The APRS message was not accepted for transmission.")
        await setup.model.releasePTT()
        setup.model.callsign = "N0CALLXX"
        setup.model.sendAPRSMessage(to: "N1CALL", text: "too long")
        #expect(setup.model.message == "The APRS message was not accepted for transmission.")
        #expect(await setup.sent.isEmpty)
    }

    @Test("a retry on another frequency fails; outside the band it waits")
    func frequencyChanges() async throws {
        let setup = Messaging()
        await setup.connect()
        setup.model.callsign = "N0CALL"
        setup.model.sendAPRSMessage(to: "N1CALL", text: "moving")
        #expect(await eventually { await setup.sent.count == 1 })
        setup.model.frequencyText = "146.52"
        await setup.model.applyFrequency()
        #expect(
            await RadioViewModelTests.eventually(setup.model) {
                $0.snapshot.isInSync && $0.snapshot.desired.freqTx == 146.52
            }
        )
        setup.advance(by: 15_000)
        // This wait failed now and then on CI only; the comment shows the state to find out why.
        let failed = await RadioViewModelTests.eventually(setup.model) { $0.aprsEvents.first?.deliveryState == .failed }
        let model = setup.model
        let events = model.aprsEvents.map { "\($0.kind) \($0.deliveryState) \($0.fromCallsign)>\($0.toCallsign ?? "")" }
        let packets =
            await setup.simulator.value?.simulator.transmittedPackets.map { "\($0.channel?.freqTx ?? 0)" } ?? []
        #expect(
            failed,
            """
            events=\(events) status=\(model.snapshot.status) tx=\(model.isTransmitting) \
            scan=\(model.isScanning) desiredTx=\(model.snapshot.desired.freqTx) \
            inSync=\(model.snapshot.isInSync) firmware=\(model.snapshot.firmware != nil) sent=\(packets) \
            message=\(model.message ?? "-") now=\(setup.time.ms)
            """
        )
        setup.model.frequencyText = "150"
        await setup.model.applyFrequency()
        #expect(await RadioViewModelTests.eventually(setup.model) { $0.snapshot.isInSync && !$0.canTransmit })
        setup.model.sendAPRSMessage(to: "CQ", text: "outside")
        #expect(setup.model.message == "The APRS message was not accepted for transmission.")
    }

    @Test("TX frequencies in hertz as Android rounds them")
    func hertz() {
        #expect(RadioViewModel.hertz(144.8) == 144_800_000)
        #expect(RadioViewModel.hertz(146.52) == 146_520_000)
    }
}
