/// Radio configuration shared by `HostDesiredState` and `DeviceState` (22 bytes).
///
/// Specification: `docs/apple/03-protocol-spec.md` §4.1.
public struct RadioState: Equatable, Sendable {
    public static let byteCount = 22

    /// Host: incremented for each new desired state. Device: the applied sequence.
    public var sequence: UInt32
    public var memoryId: Int32
    public var flags: StateFlags
    /// `0x00` = 12.5 kHz, `0x01` = 25 kHz.
    public var bandwidth: UInt8
    /// MHz.
    public var freqTx: Float
    /// MHz.
    public var freqRx: Float
    /// SA818 tone index, 0 = none.
    public var ctcssTx: UInt8
    /// 0…8.
    public var squelch: UInt8
    /// SA818 tone index, 0 = none.
    public var ctcssRx: UInt8

    public init(
        sequence: UInt32 = 0,
        memoryId: Int32 = 0,
        flags: StateFlags = [],
        bandwidth: UInt8 = 0,
        freqTx: Float = 0,
        freqRx: Float = 0,
        ctcssTx: UInt8 = 0,
        squelch: UInt8 = 0,
        ctcssRx: UInt8 = 0
    ) {
        self.sequence = sequence
        self.memoryId = memoryId
        self.flags = flags
        self.bandwidth = bandwidth
        self.freqTx = freqTx
        self.freqRx = freqRx
        self.ctcssTx = ctcssTx
        self.squelch = squelch
        self.ctcssRx = ctcssRx
    }

    public init(decoding bytes: [UInt8]) throws(ProtocolError) {
        try bytes.requireCount(Self.byteCount)
        var reader = ByteReader(bytes)
        self.init(reader: &reader)
    }

    init(reader: inout ByteReader) {
        sequence = reader.uint32()
        memoryId = Int32(bitPattern: reader.uint32())
        flags = StateFlags(rawValue: reader.uint16())
        bandwidth = reader.uint8()
        freqTx = reader.float()
        freqRx = reader.float()
        ctcssTx = reader.uint8()
        squelch = reader.uint8()
        ctcssRx = reader.uint8()
    }

    public func encoded() -> [UInt8] {
        var writer = ByteWriter()
        writer.uint32(sequence)
        writer.uint32(UInt32(bitPattern: memoryId))
        writer.uint16(flags.rawValue)
        writer.uint8(bandwidth)
        writer.float(freqTx)
        writer.float(freqRx)
        writer.uint8(ctcssTx)
        writer.uint8(squelch)
        writer.uint8(ctcssRx)
        return writer.bytes
    }
}

/// The state the host asks the device to apply (`HOST_DESIRED_STATE`).
public typealias HostDesiredState = RadioState

/// SA818 module status reported by the firmware.
public enum RadioModuleStatus: Equatable, Sendable {
    case found
    case notFound
    case unknown

    init(byte: UInt8) {
        switch byte {
        case UInt8(ascii: "f"): self = .found
        case UInt8(ascii: "x"): self = .notFound
        default: self = .unknown
        }
    }
}

/// Firmware operating mode.
public enum DeviceMode: Equatable, Sendable {
    case tx
    case rx
    case stopped
    case unknown

    init(byte: UInt8) {
        switch byte {
        case 0: self = .tx
        case 1: self = .rx
        case 2: self = .stopped
        default: self = .unknown
        }
    }
}

/// The state the device reports (`DEVICE_STATE`, 26 bytes).
///
/// Specification: `docs/apple/03-protocol-spec.md` §4.2.
public struct DeviceState: Equatable, Sendable {
    public static let byteCount = RadioState.byteCount + 4

    /// Applied configuration; `radio.sequence` is the applied host sequence.
    public var radio: RadioState
    public var radioModuleStatus: RadioModuleStatus
    public var mode: DeviceMode
    /// 0 none, 1 radio config failed, 2 filters failed.
    public var lastError: UInt8
    /// Raw SA818 RSSI, see `SMeter`.
    public var latestRssi: UInt8

    public var hasRadioConfig: Bool { radio.flags.contains(.radioConfigValid) }

    public init(decoding bytes: [UInt8]) throws(ProtocolError) {
        try bytes.requireCount(Self.byteCount)
        var reader = ByteReader(bytes)
        radio = RadioState(reader: &reader)
        radioModuleStatus = RadioModuleStatus(byte: reader.uint8())
        mode = DeviceMode(byte: reader.uint8())
        lastError = reader.uint8()
        latestRssi = reader.uint8()
    }
}

/// RF module fitted to the board.
public enum RFModuleType: UInt8, Equatable, Sendable {
    case sa818VHF = 0
    case sa818UHF = 1
}

/// Optional hardware and firmware capabilities (`Version.features`).
public struct FirmwareFeatures: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let highLowPower = FirmwareFeatures(rawValue: 1 << 0)
    public static let physicalPTT = FirmwareFeatures(rawValue: 1 << 1)
    public static let esp32AFSK = FirmwareFeatures(rawValue: 1 << 2)
    public static let freeDV2400B = FirmwareFeatures(rawValue: 1 << 3)
}

/// Firmware version and capabilities (`Version`, 17 bytes).
///
/// Specification: `docs/apple/03-protocol-spec.md` §4.3.
public struct FirmwareVersion: Equatable, Sendable {
    public static let byteCount = 17

    public var version: UInt16
    public var radioModuleStatus: RadioModuleStatus
    /// Initial flow-control window of this session.
    public var windowSize: UInt32
    public var moduleType: RFModuleType
    /// MHz.
    public var minRadioFreq: Float
    /// MHz.
    public var maxRadioFreq: Float
    public var features: FirmwareFeatures

    public init(decoding bytes: [UInt8]) throws(ProtocolError) {
        try bytes.requireCount(Self.byteCount)
        var reader = ByteReader(bytes)
        version = reader.uint16()
        radioModuleStatus = RadioModuleStatus(byte: reader.uint8())
        windowSize = reader.uint32()
        let moduleByte = reader.uint8()
        guard let moduleType = RFModuleType(rawValue: moduleByte) else { throw .unknownRFModuleType(moduleByte) }
        self.moduleType = moduleType
        minRadioFreq = reader.float()
        maxRadioFreq = reader.float()
        features = FirmwareFeatures(rawValue: reader.uint8())
    }
}

/// First message of a session (`HELLO`, 43 bytes).
public struct Hello: Equatable, Sendable {
    public static let byteCount = FirmwareVersion.byteCount + DeviceState.byteCount

    public var version: FirmwareVersion
    public var deviceState: DeviceState

    public init(decoding bytes: [UInt8]) throws(ProtocolError) {
        try bytes.requireCount(Self.byteCount)
        version = try FirmwareVersion(decoding: Array(bytes.prefix(FirmwareVersion.byteCount)))
        deviceState = try DeviceState(decoding: Array(bytes.dropFirst(FirmwareVersion.byteCount)))
    }
}

/// Flow-control credit sent by the device (`WINDOW_UPDATE`, 4 bytes).
public struct WindowUpdate: Equatable, Sendable {
    public static let byteCount = 4

    /// Encoded bytes the device consumed.
    public var size: UInt32

    public init(decoding bytes: [UInt8]) throws(ProtocolError) {
        try bytes.requireCount(Self.byteCount)
        var reader = ByteReader(bytes)
        size = reader.uint32()
    }
}
