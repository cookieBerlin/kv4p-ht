import KV4PTransport
import Synchronization

/// A transport whose connect result and received bytes are set by the test.
final class ScriptedTransport: RadioTransport {
    let streams = TransportStreams()
    private let connectError: TransportError?
    private let sentFrames = Mutex<[[UInt8]]>([])

    init(connectError: TransportError? = nil) {
        self.connectError = connectError
    }

    var states: AsyncStream<TransportState> { streams.states }

    var incoming: AsyncStream<[UInt8]> { streams.incoming }

    var sent: [[UInt8]] { sentFrames.withLock { $0 } }

    func connect() async throws(TransportError) {
        if let connectError {
            streams.publish(.failed(connectError))
            throw connectError
        }
        streams.publish(.connected)
    }

    func send(_ bytes: [UInt8]) async throws(TransportError) {
        sentFrames.withLock { $0.append(bytes) }
    }

    func disconnect() async {
        streams.publish(.disconnected)
    }
}

extension AsyncStream.Iterator {
    /// The next element matching `predicate`; `nil` if the stream ends first.
    mutating func next(where predicate: (Element) -> Bool) async -> Element? {
        while let element = await next() {
            if predicate(element) {
                return element
            }
        }
        return nil
    }
}
