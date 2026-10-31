import Foundation

/// The CoreBluetooth adapter: reports callbacks as events and executes commands, without logic of its own
/// (ADR-0018).
public protocol BLECentral: Sendable {
    /// Callbacks, starting with the power state; one consumer.
    var events: AsyncStream<BLEEvent> { get }
    func perform(_ command: BLECommand)
}

/// `RadioTransport` over the KV4P BLE GATT service.
public actor BLETransport: RadioTransport {
    private nonisolated let streams = TransportStreams()
    private let central: any BLECentral
    private let peripheral: UUID?
    private var link = BLELink()
    private var eventLoop: Task<Void, Never>?
    private var waiters: [CheckedContinuation<Result<Void, TransportError>, Never>] = []

    /// Connects to `peripheral`, or to the first kv4p HT found.
    public init(central: any BLECentral, peripheral: UUID? = nil) {
        self.central = central
        self.peripheral = peripheral
    }

    deinit {
        eventLoop?.cancel()
    }

    public nonisolated var states: AsyncStream<TransportState> { streams.states }

    public nonisolated var incoming: AsyncStream<[UInt8]> { streams.incoming }

    public func connect() async throws(TransportError) {
        startEventLoop()
        update(link.connect(to: peripheral))
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
                resumeWaiters()
            }
        } onCancel: {
            Task { await self.disconnect() }
        }
        try result.get()
    }

    public func send(_ bytes: [UInt8]) async throws(TransportError) {
        guard link.state == .connected else { throw .notConnected }
        update(link.send(bytes))
    }

    public func disconnect() async {
        update(link.disconnect())
    }

    private func startEventLoop() {
        guard eventLoop == nil else { return }
        let events = central.events
        eventLoop = Task { [weak self] in
            for await event in events {
                await self?.handle(event)
            }
        }
    }

    private func handle(_ event: BLEEvent) {
        if case .value(let bytes) = event, link.state == .connected {
            streams.deliver(bytes)
        }
        update(link.handle(event))
    }

    private func update(_ commands: [BLECommand]) {
        commands.forEach(central.perform)
        streams.publish(link.state)
        resumeWaiters()
    }

    /// Completes pending `connect` calls once the link connected, failed or was disconnected.
    private func resumeWaiters() {
        let result: Result<Void, TransportError>
        switch link.state {
        case .connecting: return
        case .connected: result = .success(())
        case .failed(let error): result = .failure(error)
        case .disconnected: result = .failure(.notConnected)
        }
        let waiting = waiters
        waiters = []
        waiting.forEach { $0.resume(returning: result) }
    }
}
