import KV4PTestSupport
import Testing

@testable import KV4PTransport

@Suite("Serial transport")
struct SerialTransportTests {
    static let lines = FakeSerialPort.Call.modemLines(dtr: true, rts: true)

    @Test("connect opens the port with DTR and RTS set, like the Android app")
    func connect() async throws {
        let port = FakeSerialPort()
        let transport = SerialTransport(port: port, clock: ManualClock())
        try await transport.connect()
        try await transport.connect()
        #expect(port.calls == [.open, Self.lines])
        port.receive([0xC0, 0x06])
        var incoming = transport.incoming.makeAsyncIterator()
        #expect(await incoming.next() == [0xC0, 0x06])
        #expect(await collect(2, from: transport.states) == [.connecting, .connected])
    }

    @Test("a reset pulse on RTS restarts the ESP32 before connecting")
    func resetOnConnect() async throws {
        let clock = ManualClock()
        let port = FakeSerialPort()
        let transport = SerialTransport(port: port, resetOnConnect: true, clock: clock)
        let attempt = Task { try await transport.connect() }
        await clock.waitForSleepers(1)
        #expect(port.calls == [.open, .modemLines(dtr: false, rts: true)])
        clock.advance(by: .milliseconds(100))
        try await attempt.value
        #expect(port.calls == [.open, .modemLines(dtr: false, rts: true), Self.lines])
    }

    @Test("cancelling during the reset pulse closes the port")
    func cancelDuringReset() async {
        let clock = ManualClock()
        let port = FakeSerialPort()
        let transport = SerialTransport(port: port, resetOnConnect: true, clock: clock)
        let attempt = Task { try await transport.connect() }
        await clock.waitForSleepers(1)
        attempt.cancel()
        await #expect(throws: TransportError.notConnected) { try await attempt.value }
        #expect(port.calls.last == .close)
    }

    @Test("a port that cannot be opened fails the connection")
    func openFails() async {
        let error = TransportError.portUnavailable(path: "/dev/cu.example", errno: 16)
        let transport = SerialTransport(port: FakeSerialPort(failures: .init(open: error)), clock: ManualClock())
        await #expect(throws: error) { try await transport.connect() }
        #expect(await collect(2, from: transport.states) == [.connecting, .failed(error)])
    }

    @Test("failing modem lines close the port")
    func modemLinesFail() async {
        let port = FakeSerialPort(failures: .init(modemLines: .ioFailed(errno: 5)))
        let transport = SerialTransport(port: port, clock: ManualClock())
        await #expect(throws: TransportError.ioFailed(errno: 5)) { try await transport.connect() }
        #expect(port.calls.last == .close)
    }

    @Test("unplugging reports a lost connection")
    func unplugged() async throws {
        let port = FakeSerialPort()
        let transport = SerialTransport(port: port, clock: ManualClock())
        try await transport.connect()
        port.unplug()
        #expect(await collect(3, from: transport.states) == [.connecting, .connected, .failed(.connectionLost)])
        await port.waitFor(.close)
    }

    @Test("send writes while connected and throws otherwise")
    func send() async throws {
        let port = FakeSerialPort()
        let transport = SerialTransport(port: port, clock: ManualClock())
        await #expect(throws: TransportError.notConnected) { try await transport.send([1]) }
        try await transport.connect()
        try await transport.send([1, 2])
        #expect(port.calls.last == .write([1, 2]))
    }

    @Test("a failing write fails the connection")
    func writeFails() async throws {
        let port = FakeSerialPort(failures: .init(write: .ioFailed(errno: 6)))
        let transport = SerialTransport(port: port, clock: ManualClock())
        try await transport.connect()
        await #expect(throws: TransportError.ioFailed(errno: 6)) { try await transport.send([1]) }
        #expect(await collect(3, from: transport.states) == [.connecting, .connected, .failed(.ioFailed(errno: 6))])
        #expect(port.calls.last == .close)
    }

    @Test("disconnect closes the port without reporting a failure")
    func disconnect() async throws {
        let port = FakeSerialPort()
        let transport = SerialTransport(port: port)
        try await transport.connect()
        await transport.disconnect()
        await transport.disconnect()
        #expect(await collect(3, from: transport.states) == [.connecting, .connected, .disconnected])
        #expect(port.calls.filter { $0 == .close }.count == 1)
        try await transport.connect()
        #expect(port.calls.filter { $0 == .open }.count == 2)
    }
}
