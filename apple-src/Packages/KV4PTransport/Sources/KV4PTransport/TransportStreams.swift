import Synchronization

/// The state and incoming streams of a transport, shared by all implementations.
public final class TransportStreams: Sendable {
    public let states: AsyncStream<TransportState>
    public let incoming: AsyncStream<[UInt8]>
    private let stateContinuation: AsyncStream<TransportState>.Continuation
    private let incomingContinuation: AsyncStream<[UInt8]>.Continuation
    private let current = Mutex(TransportState.disconnected)

    public init() {
        (states, stateContinuation) = AsyncStream.makeStream()
        (incoming, incomingContinuation) = AsyncStream.makeStream()
    }

    /// Consumers see the streams end when the transport is released.
    deinit {
        stateContinuation.finish()
        incomingContinuation.finish()
    }

    public var state: TransportState { current.withLock { $0 } }

    /// Emits `state` if it differs from the current one.
    public func publish(_ state: TransportState) {
        let changed = current.withLock { current in
            defer { current = state }
            return current != state
        }
        if changed {
            stateContinuation.yield(state)
        }
    }

    public func deliver(_ bytes: [UInt8]) {
        if !bytes.isEmpty {
            incomingContinuation.yield(bytes)
        }
    }
}
