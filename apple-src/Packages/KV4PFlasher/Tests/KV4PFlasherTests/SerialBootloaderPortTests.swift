import KV4PTestSupport
import KV4PTransport
import Testing

@testable import KV4PFlasher

/// The bootloader port over the serial adapter: reads with a timeout, as `SerialBufferedReader` with
/// `UsbSerialPort.read(…, 100)`.
@Suite("Serial bootloader port")
struct SerialBootloaderPortTests {
    @Test("baud rate, lines and writes reach the serial port")
    func forwards() async throws {
        let serial = FakeSerialPort()
        let port = SerialBootloaderPort(port: serial, clock: ManualClock())
        try await port.open()
        try await port.setBaudRate(921_600)
        try await port.setModemLines(dtr: true, rts: false)
        try await port.write([1, 2])
        await port.close()
        #expect(
            serial.calls == [.open, .baudRate(921_600), .modemLines(dtr: true, rts: false), .write([1, 2]), .close]
        )
    }

    @Test("received bytes are read at once, later ones when they arrive")
    func receives() async throws {
        let serial = FakeSerialPort()
        let port = SerialBootloaderPort(port: serial, clock: ManualClock())
        try await port.open()
        serial.receive([1, 2])
        serial.receive([3])
        #expect(await eventually { await port.buffered == 3 })
        #expect(try await port.read(timeout: .seconds(1)) == [1, 2, 3])
        let later = Task { try await port.read(timeout: .seconds(1)) }
        #expect(await eventually { await port.isWaiting })
        serial.receive([4])
        #expect(try await later.value == [4])
    }

    @Test("without bytes, a read ends empty after its timeout")
    func timeout() async throws {
        let clock = ManualClock()
        let port = SerialBootloaderPort(port: FakeSerialPort(), clock: clock)
        try await port.open()
        let read = Task { try await port.read(timeout: .milliseconds(100)) }
        await clock.waitForSleepers(1)
        clock.advance(by: .milliseconds(100))
        #expect(try await read.value == [])
    }

    @Test("an unplugged port fails reads; a port that cannot open fails at once")
    func unplugged() async throws {
        let serial = FakeSerialPort()
        let port = SerialBootloaderPort(port: serial, clock: ManualClock())
        try await port.open()
        let read = Task { try await port.read(timeout: .seconds(1)) }
        #expect(await eventually { await port.isWaiting })
        serial.unplug()
        await #expect(throws: TransportError.connectionLost) { try await read.value }
        await #expect(throws: TransportError.connectionLost) { try await port.read(timeout: .seconds(1)) }
        let missing = SerialBootloaderPort(
            port: FakeSerialPort(failures: .init(open: .portUnavailable(path: "/dev/x", errno: 2))),
            clock: ManualClock()
        )
        await #expect(throws: TransportError.portUnavailable(path: "/dev/x", errno: 2)) { try await missing.open() }
    }
}
