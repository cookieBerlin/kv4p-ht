import KV4PTransport

/// The serial port as the ESP32 ROM bootloader protocol needs it (esp32-flash-lib `SerialTransport`).
public protocol BootloaderPort: Sendable {
    func open() async throws(TransportError)
    func close() async
    func setBaudRate(_ rate: Int) async throws(TransportError)
    /// Sets DTR and RTS together; on the kv4p HT they drive `IO0` and `EN` of the ESP32.
    func setModemLines(dtr: Bool, rts: Bool) async throws(TransportError)
    func write(_ bytes: [UInt8]) async throws(TransportError)
    /// The bytes received so far, waiting at most `timeout` for some; empty if none arrived.
    func read(timeout: Duration) async throws(TransportError) -> [UInt8]
}

/// The four flash regions of the kv4p HT firmware (`FirmwareUtils.flashFirmware`).
public struct FirmwareImages: Equatable, Sendable {
    public var bootloader: [UInt8]
    public var partitions: [UInt8]
    public var bootApp0: [UInt8]
    public var app: [UInt8]

    public init(bootloader: [UInt8], partitions: [UInt8], bootApp0: [UInt8], app: [UInt8]) {
        self.bootloader = bootloader
        self.partitions = partitions
        self.bootApp0 = bootApp0
        self.app = app
    }
}

/// What a flash reports while it runs (`FirmwareCallback`).
public enum FlashEvent: Equatable, Sendable {
    /// The bootloader answered.
    case connected
    /// 0…100 over all four regions.
    case progress(Int)
}

public enum FlashError: Error, Equatable, Sendable {
    /// The ESP32 did not answer SYNC: no radio, or it is not in its bootloader.
    case noAnswer
    case timeout(opcode: UInt8)
    case commandFailed(opcode: UInt8, error: UInt8)
    /// The chip is not an ESP32 (`CHIP_DETECT_MAGIC_REG_ADDRESS`).
    case unsupportedChip(UInt32)
    /// The flasher stub did not start.
    case stubNotStarted
    /// The MD5 of the region at `offset` differs from the image.
    case verifyFailed(offset: UInt32)
    case port(TransportError)
}
