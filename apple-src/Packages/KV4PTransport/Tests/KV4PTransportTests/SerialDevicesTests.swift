import Testing

@testable import KV4PTransport

@Suite("Serial devices")
struct SerialDevicesTests {
    @Test("only USB serial call-out devices are offered, sorted")
    func candidates() {
        let names = [
            "tty.usbserial-0001", "cu.usbserial-0001", "cu.SLAB_USBtoUART", "cu.wchusbserial1410",
            "cu.usbmodem101", "cu.Bluetooth-Incoming-Port", "cu.debug-console", "null", "disk0",
        ]
        #expect(
            SerialDevices.candidates(in: names) == [
                "/dev/cu.SLAB_USBtoUART", "/dev/cu.usbmodem101", "/dev/cu.usbserial-0001",
                "/dev/cu.wchusbserial1410",
            ]
        )
    }
}
