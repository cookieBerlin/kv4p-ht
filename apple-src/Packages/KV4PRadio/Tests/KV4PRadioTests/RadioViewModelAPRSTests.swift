import Foundation
import KV4PAPRS
import KV4PSimulator
import KV4PTestSupport
import Synchronization
import Testing

@testable import KV4PRadio

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
}
