import Testing

@testable import KV4PTestSupport

@Suite("Manual clock")
struct ManualClockTests {
    @Test("sleeps started are counted, also when they end at once or are cancelled")
    func sleepCount() async throws {
        let clock = ManualClock()
        #expect(clock.sleepCount == 0)
        try await clock.sleep(for: .zero)
        let sleeper = Task { try await clock.sleep(for: .seconds(1)) }
        await clock.waitForSleepers(1)
        sleeper.cancel()
        _ = await sleeper.result
        #expect(clock.sleepCount == 2)
        #expect(clock.sleeperCount == 0)
    }

    @Test("time only moves when advanced")
    func advance() {
        let clock = ManualClock()
        let start = clock.now
        clock.advance(by: .milliseconds(250))
        #expect(start.duration(to: clock.now) == .milliseconds(250))
        #expect(clock.now.advanced(by: .seconds(-1)) < clock.now)
        #expect(clock.minimumResolution == .zero)
    }

    @Test("a deadline in the past returns at once")
    func pastDeadline() async throws {
        let clock = ManualClock()
        try await clock.sleep(until: clock.now, tolerance: nil)
        #expect(clock.sleeperCount == 0)
    }

    @Test("a sleeper wakes once its deadline is reached")
    func wakesAtDeadline() async throws {
        let clock = ManualClock()
        let sleeper = Task { try await clock.sleep(for: .milliseconds(100)) }
        await clock.waitForSleepers(1)
        clock.advance(by: .milliseconds(99))
        #expect(clock.sleeperCount == 1)
        clock.advance(by: .milliseconds(1))
        try await sleeper.value
        #expect(clock.sleeperCount == 0)
    }

    @Test("cancelling a sleeper throws CancellationError")
    func cancellation() async {
        let clock = ManualClock()
        let sleeper = Task { try await clock.sleep(for: .seconds(1)) }
        await clock.waitForSleepers(1)
        sleeper.cancel()
        await #expect(throws: CancellationError.self) { try await sleeper.value }
        #expect(clock.sleeperCount == 0)
    }

    @Test("a task cancelled before sleeping throws at once")
    func cancelledBeforeSleeping() async {
        let clock = ManualClock()
        let sleeper = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await clock.sleep(for: .seconds(1))
        }
        await #expect(throws: CancellationError.self) { try await sleeper.value }
    }
}
