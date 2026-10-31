import KV4PTransport

/// `CBPeripheralManager` callbacks, as reported by the adapter.
public enum PeripheralEvent: Equatable, Sendable {
    case powerState(BLEPowerState)
    case serviceAdded(Bool)
    /// A central subscribed to the RX characteristic; its `maximumUpdateValueLength`.
    case subscribed(maximumUpdateLength: Int)
    case unsubscribed
    /// A write to the TX characteristic; the adapter answers write requests itself.
    case write([UInt8])
    /// The result of `updateValue`; `false` if the transmit queue is full.
    case notified(Bool)
    /// `peripheralManagerIsReady(toUpdateSubscribers:)`.
    case readyToUpdate
}

/// `CBPeripheralManager` calls for the adapter to execute.
public enum PeripheralCommand: Equatable, Sendable {
    /// Publish the KV4P service with its TX and RX characteristics.
    case addService
    case startAdvertising
    case stopAdvertising
    /// Notify the subscribed central on the RX characteristic.
    case notify([UInt8])
}

/// The GATT peripheral side of the simulator (ADR-0014 B) as a pure state machine (ADR-0018): like the
/// firmware, it serves one central, starts the session on the notify subscription and advertises again after it.
public struct PeripheralLink: Sendable {
    public private(set) var simulator: RadioSimulator
    public private(set) var isAdvertising = false
    public private(set) var isSubscribed = false
    /// The service could not be published.
    public private(set) var failed = false

    private var serviceRequested = false
    private var updateLength = 20
    private var pending: [UInt8] = []
    private var inFlight: [UInt8]?
    private var waitingForRoom = false

    public init(simulator: RadioSimulator) {
        self.simulator = simulator
    }

    public mutating func handle(_ event: PeripheralEvent, at now: Duration) -> [PeripheralCommand] {
        switch event {
        case .powerState(.poweredOn):
            guard !serviceRequested else { return [] }
            serviceRequested = true
            return [.addService]
        case .powerState:
            // Without power the published service is gone; it is added again on the next power-on.
            endSession(at: now)
            serviceRequested = false
            isAdvertising = false
            return []
        case .serviceAdded(let added):
            failed = !added
            isAdvertising = added
            return added ? [.startAdvertising] : []
        case .subscribed(let maximumUpdateLength):
            guard !isSubscribed else { return [] }
            isSubscribed = true
            isAdvertising = false
            updateLength = maximumUpdateLength
            return [.stopAdvertising] + enqueue(simulator.connect(at: now))
        case .unsubscribed:
            guard isSubscribed else { return [] }
            endSession(at: now)
            isAdvertising = true
            return [.startAdvertising]
        case .write(let bytes):
            guard isSubscribed else { return [] }
            return enqueue(simulator.receive(bytes, at: now))
        case .notified(true):
            guard inFlight != nil else { return [] }
            inFlight = nil
            return flush()
        case .notified(false):
            waitingForRoom = inFlight != nil
            return []
        case .readyToUpdate:
            guard waitingForRoom, let chunk = inFlight else { return [] }
            waitingForRoom = false
            return [.notify(chunk)]
        }
    }

    /// Lets simulated time pass; output is only notified while a central is subscribed.
    public mutating func advance(to now: Duration) -> [PeripheralCommand] {
        let output = simulator.advance(to: now)
        return isSubscribed ? enqueue(output) : []
    }

    private mutating func endSession(at now: Duration) {
        guard isSubscribed else { return }
        _ = simulator.disconnect(at: now)
        isSubscribed = false
        pending = []
        inFlight = nil
        waitingForRoom = false
    }

    private mutating func enqueue(_ bytes: [UInt8]) -> [PeripheralCommand] {
        pending += bytes
        return flush()
    }

    /// Notifies the next chunk once the previous one was accepted.
    private mutating func flush() -> [PeripheralCommand] {
        guard inFlight == nil, !pending.isEmpty else { return [] }
        let chunk = Array(pending.prefix(updateLength))
        pending.removeFirst(chunk.count)
        inFlight = chunk
        return [.notify(chunk)]
    }
}
