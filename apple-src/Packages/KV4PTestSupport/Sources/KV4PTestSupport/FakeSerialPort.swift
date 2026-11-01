import KV4PTransport
import Synchronization

/// A serial port that records calls; tests feed received bytes and unplug it.
public final class FakeSerialPort: SerialPort {
    public enum Call: Equatable, Sendable {
        case open
        case baudRate(Int)
        case modemLines(dtr: Bool, rts: Bool)
        case write([UInt8])
        case close
    }

    public struct Failures: Sendable {
        public var open: TransportError?
        public var modemLines: TransportError?
        public var write: TransportError?

        public init(open: TransportError? = nil, modemLines: TransportError? = nil, write: TransportError? = nil) {
            self.open = open
            self.modemLines = modemLines
            self.write = write
        }
    }

    private struct State {
        var calls: [Call] = []
        var continuation: AsyncStream<[UInt8]>.Continuation?
    }

    private let state = Mutex(State())
    private let failures: Failures

    public init(failures: Failures = Failures()) {
        self.failures = failures
    }

    public var calls: [Call] { state.withLock { $0.calls } }

    public func open() throws(TransportError) -> AsyncStream<[UInt8]> {
        record(.open)
        if let error = failures.open { throw error }
        let (stream, continuation) = AsyncStream.makeStream(of: [UInt8].self)
        state.withLock { $0.continuation = continuation }
        return stream
    }

    public func setBaudRate(_ rate: Int) throws(TransportError) {
        record(.baudRate(rate))
    }

    public func setModemLines(dtr: Bool, rts: Bool) throws(TransportError) {
        record(.modemLines(dtr: dtr, rts: rts))
        if let error = failures.modemLines { throw error }
    }

    public func write(_ bytes: [UInt8]) throws(TransportError) {
        record(.write(bytes))
        if let error = failures.write { throw error }
    }

    public func close() {
        record(.close)
        unplug()
    }

    public func receive(_ bytes: [UInt8]) {
        _ = state.withLock { $0.continuation?.yield(bytes) }
    }

    /// The read stream ends, as when the cable is pulled.
    public func unplug() {
        state.withLock { $0.continuation?.finish() }
    }

    public func waitFor(_ call: Call) async {
        while !calls.contains(call) {
            await Task.yield()
        }
    }

    private func record(_ call: Call) {
        state.withLock { $0.calls.append(call) }
    }
}
