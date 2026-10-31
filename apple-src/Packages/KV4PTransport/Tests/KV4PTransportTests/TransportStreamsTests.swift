import Testing

@testable import KV4PTransport

@Suite("Transport streams")
struct TransportStreamsTests {
    @Test("only changes are published")
    func publishesChanges() async {
        var streams: TransportStreams? = TransportStreams()
        let states = streams?.states
        streams?.publish(.disconnected)
        streams?.publish(.connecting)
        streams?.publish(.connecting)
        #expect(streams?.state == .connecting)
        streams = nil
        var received: [TransportState] = []
        for await state in states ?? AsyncStream { $0.finish() } {
            received.append(state)
        }
        #expect(received == [.connecting])
    }

    @Test("both streams finish when the transport is released")
    func finishOnRelease() async {
        var streams: TransportStreams? = TransportStreams()
        let incoming = streams?.incoming
        streams?.deliver([1])
        streams = nil
        var received: [[UInt8]] = []
        for await bytes in incoming ?? AsyncStream { $0.finish() } {
            received.append(bytes)
        }
        #expect(received == [[1]])
    }
}
