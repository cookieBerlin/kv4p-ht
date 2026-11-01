import Synchronization

/// A `Clock` that only advances when told to, so tests control timeouts and periodic work without sleeping.
public final class ManualClock: Clock, Sendable {
    public struct Instant: InstantProtocol {
        let offset: Duration

        public func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        public func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        public static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    private struct Sleeper {
        let id: Int
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now = Instant(offset: .zero)
        var sleepers: [Sleeper] = []
        /// Sleepers cancelled before they were registered.
        var cancelled: Set<Int> = []
        var nextID = 0
    }

    private let state = Mutex(State())

    public init() {}

    public var now: Instant { state.withLock { $0.now } }

    public var minimumResolution: Duration { .zero }

    public var sleeperCount: Int { state.withLock { $0.sleepers.count } }

    /// The sleeps started so far, including those already woken or cancelled: a task that replaces its timer has
    /// started a new sleep before the old one is gone.
    public var sleepCount: Int { state.withLock { $0.nextID } }

    public func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        let id = state.withLock { state in
            defer { state.nextID += 1 }
            return state.nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let result: Result<Bool, CancellationError> = state.withLock { state in
                    if state.cancelled.remove(id) != nil { return .failure(CancellationError()) }
                    if deadline <= state.now { return .success(true) }
                    state.sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    return .success(false)
                }
                switch result {
                case .success(true): continuation.resume()
                case .success(false): break
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            cancel(id)
        }
    }

    /// Moves time forward and wakes every sleeper whose deadline has been reached.
    public func advance(by duration: Duration) {
        let due = state.withLock { state in
            state.now = state.now.advanced(by: duration)
            let now = state.now
            let due = state.sleepers.filter { $0.deadline <= now }
            state.sleepers.removeAll { $0.deadline <= now }
            return due
        }
        for sleeper in due {
            sleeper.continuation.resume()
        }
    }

    /// Waits until at least `count` tasks sleep on this clock.
    public func waitForSleepers(_ count: Int) async {
        while sleeperCount < count {
            await Task.yield()
        }
    }

    private func cancel(_ id: Int) {
        let sleeper: Sleeper? = state.withLock { state in
            guard let index = state.sleepers.firstIndex(where: { $0.id == id }) else {
                state.cancelled.insert(id)
                return nil
            }
            return state.sleepers.remove(at: index)
        }
        sleeper?.continuation.resume(throwing: CancellationError())
    }
}
