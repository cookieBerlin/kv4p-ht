import Synchronization

@testable import KV4PTransport

/// A serial port that records calls; tests feed received bytes and unplug it.
final class FakeSerialPort: SerialPort {
    enum Call: Equatable {
        case open
        case modemLines(dtr: Bool, rts: Bool)
        case write([UInt8])
        case close
    }

    struct Failures {
        var open: TransportError?
        var modemLines: TransportError?
        var write: TransportError?
    }

    private struct State {
        var calls: [Call] = []
        var continuation: AsyncStream<[UInt8]>.Continuation?
    }

    private let state = Mutex(State())
    private let failures: Failures

    init(failures: Failures = Failures()) {
        self.failures = failures
    }

    var calls: [Call] { state.withLock { $0.calls } }

    func open() throws(TransportError) -> AsyncStream<[UInt8]> {
        record(.open)
        if let error = failures.open { throw error }
        let (stream, continuation) = AsyncStream.makeStream(of: [UInt8].self)
        state.withLock { $0.continuation = continuation }
        return stream
    }

    func setModemLines(dtr: Bool, rts: Bool) throws(TransportError) {
        record(.modemLines(dtr: dtr, rts: rts))
        if let error = failures.modemLines { throw error }
    }

    func write(_ bytes: [UInt8]) throws(TransportError) {
        record(.write(bytes))
        if let error = failures.write { throw error }
    }

    func close() {
        record(.close)
        unplug()
    }

    func receive(_ bytes: [UInt8]) {
        _ = state.withLock { $0.continuation?.yield(bytes) }
    }

    /// The read stream ends, as when the cable is pulled.
    func unplug() {
        state.withLock { $0.continuation?.finish() }
    }

    func waitFor(_ call: Call) async {
        while !calls.contains(call) {
            await Task.yield()
        }
    }

    private func record(_ call: Call) {
        state.withLock { $0.calls.append(call) }
    }
}
