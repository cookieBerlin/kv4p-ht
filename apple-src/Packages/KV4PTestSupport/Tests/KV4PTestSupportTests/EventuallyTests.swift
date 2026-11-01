import KV4PTestSupport
import Synchronization
import Testing

@Suite("Eventually")
struct EventuallyTests {
    @Test("true as soon as the condition holds")
    func holds() async {
        let checks = Mutex(0)
        #expect(
            await eventually {
                checks.withLock { $0 += 1 }
                return checks.withLock { $0 } == 3
            }
        )
        #expect(checks.withLock { $0 } == 3)
    }

    @Test("false when the condition does not hold before the timeout")
    func timesOut() async {
        #expect(await !eventually(timeout: .zero) { false })
    }
}
