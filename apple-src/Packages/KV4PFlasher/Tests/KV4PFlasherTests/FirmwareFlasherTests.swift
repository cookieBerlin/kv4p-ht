import Foundation
import KV4PProtocol
import KV4PTestSupport
import KV4PTransport
import Synchronization
import Testing

@testable import KV4PFlasher

/// The packaged firmware and flashing it over a serial device path.
@Suite("Firmware flasher")
struct FirmwareFlasherTests {
    static let images = FirmwareImages(bootloader: [1], partitions: [2], bootApp0: [3], app: [4])

    @Test("the packaged images are read with Android's resource names")
    func packaged() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(
            FirmwareImages.packagedFileNames == [
                "bootloader.bin", "partitions.bin", "boot_app0.bin", "firmware_v\(KV4P.packagedFirmwareVersion).bin",
            ]
        )
        for (index, name) in FirmwareImages.packagedFileNames.enumerated() {
            #expect(FirmwareImages.packaged(in: directory) == nil)
            try Data([UInt8(index + 1)]).write(to: directory.appending(path: name))
        }
        #expect(FirmwareImages.packaged(in: directory) == Self.images)
    }

    @Test("the recorded flash succeeds through the device path")
    func flashes() async throws {
        let vector = try FlasherVectorTests.vector("flash")
        let clock = VirtualClock()
        let port = TranscriptPort(transcript: vector.expected.transcript, clock: clock)
        let flasher = FirmwareFlasher(images: try vector.input.images, stub: try .esp32(), clock: clock) { path in
            #expect(path == "/dev/cu.usbserial-0001")
            return port
        }
        let percent = Mutex(0)
        try await flasher.flash(serialPath: "/dev/cu.usbserial-0001") { event in
            if case .progress(let value) = event { percent.withLock { $0 = value } }
        }
        #expect(percent.withLock { $0 } == 100)
    }

    @Test("a radio that does not answer: the port is opened, reset into the bootloader and closed again")
    func noAnswer() async {
        let serial = FakeSerialPort()
        let clock = VirtualClock()
        let flasher = FirmwareFlasher(images: Self.images, stub: FlasherStub(), clock: clock) { _ in
            SerialBootloaderPort(port: serial, clock: clock)
        }
        await #expect(throws: FlashError.noAnswer) {
            try await flasher.flash(serialPath: "/dev/cu.usbserial-0001") { _ in }
        }
        let calls = serial.calls
        #expect(calls.first == .open)
        #expect(calls.dropFirst().first == .baudRate(ESP32Flasher<VirtualClock>.romBaudRate))
        #expect(calls.filter { if case .write = $0 { true } else { false } }.count == 20)
        #expect(calls.last == .close)
    }

    @Test("a port that cannot be opened fails the flash")
    func portUnavailable() async {
        let failure = TransportError.portUnavailable(path: "/dev/x", errno: 16)
        let clock = VirtualClock()
        let flasher = FirmwareFlasher(images: Self.images, stub: FlasherStub(), clock: clock) { _ in
            SerialBootloaderPort(port: FakeSerialPort(failures: .init(open: failure)), clock: clock)
        }
        await #expect(throws: FlashError.port(failure)) { try await flasher.flash(serialPath: "/dev/x") { _ in } }
    }
}

extension FlasherStub {
    /// An empty stub, for flashes that never load it.
    init() {
        self.init(text: Data(), textStart: 0, data: Data(), dataStart: 0, entry: 0)
    }
}
