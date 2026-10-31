/// Host → device flow control (`docs/apple/03-protocol-spec.md` §6).
///
/// Before writing a frame the sender reserves its encoded length; the window is set from
/// `FirmwareVersion.windowSize` on `HELLO` and enlarged by every `WINDOW_UPDATE`.
/// Waiting senders are served in order.
public actor FlowControlWindow {
    /// Window before the first `HELLO`, as in the Android sender.
    public static let defaultSize = 1024

    private struct Waiter {
        let id: UInt64
        let size: Int
        let continuation: CheckedContinuation<Void, any Error>
    }

    public private(set) var available: Int
    private var waiters: [Waiter] = []
    private var nextID: UInt64 = 0

    /// Number of senders waiting for room.
    public var waiting: Int { waiters.count }

    public init(size: Int = defaultSize) {
        available = size
    }

    /// Waits until the window has room for `size` bytes, then subtracts them.
    /// Throws `CancellationError` if the task is cancelled before that.
    public func reserve(_ size: Int) async throws {
        try Task.checkCancellation()
        if waiters.isEmpty && available >= size {
            available -= size
            return
        }
        let id = nextID
        nextID += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append(Waiter(id: id, size: size, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    /// Sets the window, e.g. from `FirmwareVersion.windowSize`.
    public func set(_ size: Int) {
        available = size
        resumeWaiters()
    }

    /// Adds the credit of a `WINDOW_UPDATE`.
    public func enlarge(by size: Int) {
        available += size
        resumeWaiters()
    }

    private func resumeWaiters() {
        while let first = waiters.first, available >= first.size {
            waiters.removeFirst()
            available -= first.size
            first.continuation.resume()
        }
    }

    private func cancel(_ id: UInt64) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
        resumeWaiters()
    }
}
