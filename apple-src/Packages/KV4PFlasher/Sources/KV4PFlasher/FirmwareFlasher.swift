import Foundation
import KV4PProtocol
import KV4PTransport

extension FirmwareImages {
    /// The Android app's raw resources (`FirmwareUtils`), in flash order; the app bundles the same files.
    public static var packagedFileNames: [String] {
        ["bootloader.bin", "partitions.bin", "boot_app0.bin", "firmware_v\(KV4P.packagedFirmwareVersion).bin"]
    }

    /// The packaged images in `directory`; `nil` if one is missing.
    public static func packaged(in directory: URL) -> FirmwareImages? {
        let images = packagedFileNames.compactMap { name in
            FileManager.default.contents(atPath: directory.appending(path: name).path).map { Array($0) }
        }
        guard images.count == packagedFileNames.count else { return nil }
        return FirmwareImages(bootloader: images[0], partitions: images[1], bootApp0: images[2], app: images[3])
    }
}

/// Updates the firmware of the radio on a USB serial device.
public protocol FirmwareFlashing: Sendable {
    func flash(serialPath: String, events: @Sendable (FlashEvent) -> Void) async throws(FlashError)
}

/// Flashes `images` into the radio on a USB serial device; the port is open only while flashing.
public struct FirmwareFlasher<C: Clock>: FirmwareFlashing where C.Duration == Duration {
    private let images: FirmwareImages
    private let stub: FlasherStub
    private let clock: C
    private let makePort: @Sendable (String) -> any BootloaderPort

    /// `port` makes the port of a device path, e.g. `SerialBootloaderPort` over `POSIXSerialPort`.
    public init(
        images: FirmwareImages,
        stub: FlasherStub,
        clock: C,
        port: @escaping @Sendable (_ path: String) -> any BootloaderPort
    ) {
        self.images = images
        self.stub = stub
        self.clock = clock
        makePort = port
    }

    public func flash(serialPath: String, events: @Sendable (FlashEvent) -> Void) async throws(FlashError) {
        let port = makePort(serialPath)
        do throws(TransportError) { try await port.open() } catch { throw .port(error) }
        let result: Result<Void, FlashError>
        do throws(FlashError) {
            try await ESP32Flasher(port: port, clock: clock, stub: stub).flash(images, events: events)
            result = .success(())
        } catch {
            result = .failure(error)
        }
        await port.close()
        try result.get()
    }
}
