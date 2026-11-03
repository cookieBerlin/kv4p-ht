import KV4PFlasher
import Synchronization
import Testing

@testable import KV4PRadio

/// A firmware update of the simulator, which runs like a real one.
@Suite("Simulated firmware flasher")
struct SimulatedFirmwareFlasherTests {
    @Test("it connects, then reports progress up to 100 %")
    func progress() async throws {
        let events = Mutex<[FlashEvent]>([])
        let flasher = SimulatedFirmwareFlasher(step: .zero)
        try await flasher.flash(serialPath: "") { event in events.withLock { $0.append(event) } }
        let seen = events.withLock { $0 }
        #expect(seen.first == .connected)
        #expect(seen.last == .progress(100))
        #expect(seen.count == 12)
    }
}
