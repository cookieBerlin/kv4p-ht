/// Connection state of a transport.
public enum TransportState: Equatable, Sendable {
    case disconnected
    case connecting
    /// Bytes can be sent; the device sends `HELLO` next.
    case connected
    case failed(TransportError)
}

public enum TransportError: Error, Equatable, Sendable {
    case bluetoothUnavailable(BLEPowerState)
    case connectionFailed
    /// The device lacks the KV4P service or one of its characteristics.
    case serviceNotFound
    case subscriptionFailed
    case connectionLost
    case notConnected
    /// The serial port could not be opened (`errno`).
    case portUnavailable(path: String, errno: Int32)
    /// A read or write failed (`errno`).
    case ioFailed(errno: Int32)
}

/// A byte-stream connection to the device (ADR-0002, ADR-0018).
///
/// Each stream has a single consumer.
public protocol RadioTransport: Sendable {
    /// State changes, starting with the next change.
    var states: AsyncStream<TransportState> { get }
    /// Raw device → host bytes; KISS frames may span chunks.
    var incoming: AsyncStream<[UInt8]> { get }
    /// Returns once connected; throws if the connection fails or is cancelled.
    func connect() async throws(TransportError)
    func send(_ bytes: [UInt8]) async throws(TransportError)
    func disconnect() async
}
