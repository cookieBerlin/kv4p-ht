import Foundation
import KV4PRadio
import os

/// Measures the start of the app, step by step: as intervals for Instruments ("App Launch", points of interest), and as
/// one line of the log once the first frame is there, so that what holds it up shows also without Instruments.
@MainActor
enum LaunchTrace {
    private static let signposter = OSSignposter(
        subsystem: "io.github.cookieberlin.kv4pht",
        category: .pointsOfInterest
    )
    private static var times = LaunchTimes()
    private static var isReported = false
    /// When the app's own code was done, to tell its part of the start from what SwiftUI does after it.
    private static var appCodeDone: ContinuousClock.Instant?

    /// Runs one step of the start and notes how long it took.
    static func measure<T>(_ name: StaticString, _ work: () throws -> T) rethrows -> T {
        let interval = signposter.beginInterval(name)
        let start = ContinuousClock.now
        defer {
            times.record("\(name)", ContinuousClock.now - start)
            signposter.endInterval(name, interval)
        }
        return try work()
    }

    /// The app's own code starts: what came before, loading the libraries and the system's setup, counts as one step.
    static func appCodeStarts() {
        if let before = sinceProcessStart() {
            times.record("before the app's code", before)
        }
    }

    /// The app's own code is done; what follows until the first frame counts as one step.
    static func appCodeEnds() {
        appCodeDone = ContinuousClock.now
    }

    /// Once, when the first frame is about to show: the time since the process started, and the steps so far.
    static func firstFrame(log: (String) -> Void) {
        guard !isReported else { return }
        isReported = true
        if let appCodeDone {
            times.record("until the first frame", ContinuousClock.now - appCodeDone)
        }
        signposter.emitEvent("First frame")
        log(times.summary(firstFrameAfter: sinceProcessStart()))
    }

    /// The time since the system started this process; `nil` where it cannot tell.
    private static func sinceProcessStart() -> Duration? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, u_int(name.count), &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        let started = Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000
        let elapsed = Date.now.timeIntervalSince1970 - started
        return elapsed > 0 ? .milliseconds(Int64(elapsed * 1_000)) : nil
    }
}
