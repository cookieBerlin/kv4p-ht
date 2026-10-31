import Foundation
import KV4PTestSupport
import Testing

@testable import KV4PTransport

@Suite("BLE transport")
struct BLETransportTests {
    @Test("connect runs the sequence and reports connecting, then connected")
    func connect() async throws {
        let central = FakeCentral()
        let transport = BLETransport(central: central)
        var states = transport.states.makeAsyncIterator()
        try await transport.connect()
        #expect(await states.next() == .connecting)
        #expect(await states.next() == .connected)
        #expect(
            central.commands == [
                .scan, .stopScan, .connect(FakeCentral.device), .discoverService, .discoverCharacteristics,
                .enableNotifications,
            ]
        )
        try await transport.connect()
        #expect(central.commands.count == 6)
    }

    @Test("a target peripheral is passed to the link")
    func targetPeripheral() async throws {
        let other = UUID()
        let central = FakeCentral { command in
            command == .scan ? [.discovered(FakeCentral.device), .discovered(other)] : FakeCentral.kv4p(command)
        }
        try await BLETransport(central: central, peripheral: other).connect()
        #expect(central.commands.contains(.connect(other)))
    }

    @Test("connect throws the failure of the link")
    func connectFails() async {
        let central = FakeCentral { command in
            command == .discoverService ? [.serviceDiscovered(false)] : FakeCentral.kv4p(command)
        }
        let transport = BLETransport(central: central)
        await #expect(throws: TransportError.serviceNotFound) { try await transport.connect() }
    }

    @Test("connect fails at once if Bluetooth is off")
    func bluetoothOff() async {
        let transport = BLETransport(central: FakeCentral(power: .poweredOff))
        await #expect(throws: TransportError.bluetoothUnavailable(.poweredOff)) { try await transport.connect() }
    }

    @Test("notifications are delivered while connected")
    func incoming() async throws {
        let central = FakeCentral()
        let transport = BLETransport(central: central)
        central.emit(.value([0xFF]))
        try await transport.connect()
        central.emit(.value([0xC0, 0x01]))
        central.emit(.value([]))
        central.emit(.value([0xC0]))
        var incoming = transport.incoming.makeAsyncIterator()
        #expect(await incoming.next() == [0xC0, 0x01])
        #expect(await incoming.next() == [0xC0])
    }

    @Test("send writes chunks while connected and throws otherwise")
    func send() async throws {
        let central = FakeCentral()
        let transport = BLETransport(central: central)
        await #expect(throws: TransportError.notConnected) { try await transport.send([1]) }
        try await transport.connect()
        try await transport.send(Array(repeating: 7, count: 300))
        await central.waitFor(.write(Array(repeating: 7, count: 56), withResponse: false))
        #expect(central.commands.contains(.write(Array(repeating: 7, count: 244), withResponse: false)))
    }

    @Test("disconnect cancels the connection")
    func disconnect() async throws {
        let central = FakeCentral()
        let transport = BLETransport(central: central)
        try await transport.connect()
        await transport.disconnect()
        #expect(await collect(3, from: transport.states) == [.connecting, .connected, .disconnected])
        #expect(central.commands.last == .cancelConnection)
    }

    @Test("a lost connection is reported")
    func connectionLost() async throws {
        let central = FakeCentral()
        let transport = BLETransport(central: central)
        try await transport.connect()
        central.emit(.disconnected)
        #expect(await collect(3, from: transport.states) == [.connecting, .connected, .failed(.connectionLost)])
    }

    @Test("cancelling a pending connect stops scanning and throws")
    func cancelConnect() async {
        let central = FakeCentral { _ in [] }
        let transport = BLETransport(central: central)
        let attempt = Task { try await transport.connect() }
        await central.waitFor(.scan)
        attempt.cancel()
        await #expect(throws: TransportError.notConnected) { try await attempt.value }
        #expect(central.commands.last == .stopScan)
    }
}
