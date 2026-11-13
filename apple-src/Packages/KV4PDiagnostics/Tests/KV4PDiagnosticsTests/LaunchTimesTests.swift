import Testing

@testable import KV4PDiagnostics

/// How long the app took to start, step by step, as one line of the log.
@Suite("Launch times")
struct LaunchTimesTests {
    @Test("the line gives the time to the first frame, then the steps, slowest first, in whole milliseconds")
    func summary() {
        var times = LaunchTimes()
        times.record("audio", .microseconds(12_400))
        times.record("memories", .milliseconds(820))
        times.record("APRS history", .microseconds(300_600))
        #expect(
            times.summary(firstFrameAfter: .milliseconds(1_234))
                == "Launch: first frame after 1234 ms; memories 820 ms, APRS history 301 ms, audio 12 ms"
        )
    }

    @Test("without a known start of the process, the line gives the steps alone")
    func withoutFirstFrame() {
        var times = LaunchTimes()
        times.record("memories", .milliseconds(5))
        #expect(times.summary(firstFrameAfter: nil) == "Launch: memories 5 ms")
    }

    @Test("a step measured twice counts with both times together")
    func repeatedStep() {
        var times = LaunchTimes()
        times.record("store", .milliseconds(2))
        times.record("store", .milliseconds(3))
        #expect(times.summary(firstFrameAfter: nil) == "Launch: store 5 ms")
    }

    @Test("without steps, the line gives the first frame alone")
    func withoutSteps() {
        #expect(LaunchTimes().summary(firstFrameAfter: .milliseconds(80)) == "Launch: first frame after 80 ms")
    }
}
