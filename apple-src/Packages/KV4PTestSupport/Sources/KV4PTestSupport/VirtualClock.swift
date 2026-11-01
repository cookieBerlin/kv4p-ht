import Synchronization

/// A `Clock` whose sleeps return at once and move time to their deadline, for code that runs through timeouts and
/// delays one after another (e.g. a serial protocol).
public final class VirtualClock: Clock, Sendable {
    public typealias Instant = ManualClock.Instant

    private let time = Mutex(Instant(offset: .zero))

    public init() {}

    public var now: Instant { time.withLock { $0 } }

    public var minimumResolution: Duration { .zero }

    public func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        try Task.checkCancellation()
        time.withLock { $0 = max($0, deadline) }
    }
}
