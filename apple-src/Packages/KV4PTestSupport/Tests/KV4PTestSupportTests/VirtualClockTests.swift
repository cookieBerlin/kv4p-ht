import Testing

@testable import KV4PTestSupport

@Suite("Virtual clock")
struct VirtualClockTests {
    @Test("sleeping moves time to the deadline at once")
    func sleepAdvances() async throws {
        let clock = VirtualClock()
        let start = clock.now
        try await clock.sleep(for: .milliseconds(100))
        try await clock.sleep(until: start, tolerance: nil)
        #expect(start.duration(to: clock.now) == .milliseconds(100))
        #expect(clock.minimumResolution == .zero)
    }

    @Test("a cancelled sleep throws and leaves the time")
    func cancelled() async {
        let clock = VirtualClock()
        let start = clock.now
        let sleeper = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await clock.sleep(for: .seconds(1))
        }
        await #expect(throws: CancellationError.self) { try await sleeper.value }
        #expect(clock.now == start)
    }
}
