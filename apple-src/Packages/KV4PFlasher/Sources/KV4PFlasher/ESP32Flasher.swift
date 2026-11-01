import CryptoKit
import KV4PProtocol
import KV4PTransport
import zlib

/// Flashes the kv4p HT's ESP32 through its ROM bootloader as the Android app does: `FirmwareUtils.flashFirmware`
/// with esp32-flash-lib's `EspFlasherProtocol` (esptool serial protocol). Pinned by `flasher.json`.
public struct ESP32Flasher<C: Clock>: Sendable where C.Duration == Duration {
    /// `ESP_ROM_BAUD`.
    public static var romBaudRate: Int { 115_200 }
    /// `ESP_ROM_BAUD_HIGHEST`, used once the bootloader answered.
    public static var flashBaudRate: Int { 921_600 }

    private let port: any BootloaderPort
    private let clock: C
    private let stub: FlasherStub

    public init(port: any BootloaderPort, clock: C, stub: FlasherStub) {
        self.port = port
        self.clock = clock
        self.stub = stub
    }

    /// Resets the ESP32 into its bootloader, writes and verifies the four regions, then restarts it.
    public func flash(_ images: FirmwareImages, events: (FlashEvent) -> Void) async throws(FlashError) {
        var session = Session(port: port, clock: clock)
        var progress = Progress(
            sizes: [images.bootloader, images.partitions, images.bootApp0, images.app].map(\.count)
        )
        try await session.setBaudRate(Self.romBaudRate)
        try await session.enterBootloader()
        try await session.sync()
        events(.connected)
        try await session.changeBaudRate(Self.flashBaudRate)
        try await session.detectChip()
        try await session.loadStub(stub)
        let regions = [
            (images.bootloader, Region.bootloader, false),
            (images.partitions, Region.partitionTable, false),
            (images.bootApp0, Region.appBootloader, false),
            (images.app, Region.app0, true),
        ]
        for (image, offset, compressed) in regions {
            try await session.write(image, at: offset, compressed: compressed) {
                events(.progress(progress.percent($0)))
            }
            progress.endRegion()
            try await session.verify(image, at: offset)
        }
        try await session.reset()
    }

    /// `FirmwareUtils.getProgressCallback`: the percentage over all regions, weighted by size.
    struct Progress {
        let sizes: [Int]
        private var part = 0
        private var completed = 0

        init(sizes: [Int]) {
            self.sizes = sizes
        }

        /// `Math.round` of Android's float arithmetic.
        func percent(_ regionPercent: Float) -> Int {
            let total = Float(sizes.reduce(0, +))
            let value = (Float(completed) + Float(sizes[part]) * (regionPercent / 100)) * 100 / total
            return Int((value + 0.5).rounded(.down))
        }

        mutating func endRegion() {
            part += 1
            completed = sizes.prefix(part).reduce(0, +)
        }
    }
}

/// `Esp32ChipId.ESP32` flash offsets.
enum Region {
    static let bootloader: UInt32 = 0x1000
    static let partitionTable: UInt32 = 0x8000
    static let appBootloader: UInt32 = 0xE000
    static let app0: UInt32 = 0x10000
}

/// ROM bootloader commands (`RomCommand`).
enum Opcode {
    static let flashBegin: UInt8 = 0x02
    static let flashData: UInt8 = 0x03
    static let memBegin: UInt8 = 0x05
    static let memEnd: UInt8 = 0x06
    static let memData: UInt8 = 0x07
    static let sync: UInt8 = 0x08
    static let readReg: UInt8 = 0x0A
    static let changeBaudRate: UInt8 = 0x0F
    static let flashDeflBegin: UInt8 = 0x10
    static let flashDeflData: UInt8 = 0x11
    static let spiFlashMD5: UInt8 = 0x13
}

/// The command layer of `EspFlasherProtocol`.
struct Session<C: Clock> where C.Duration == Duration {
    static var syncAttempts: Int { 20 }
    static var resetDelay: Duration { .milliseconds(100) }
    static var shortTimeout: Duration { .milliseconds(100) }
    static var flashBlockSize: Int { 0x4000 }
    static var memBlockSize: Int { 0x1800 }
    static var chipDetectRegister: UInt32 { 0x4000_1000 }
    static var esp32Magic: UInt32 { 0x00F0_1D83 }
    /// The stub's greeting after `MEM_END`.
    static var stubGreeting: [UInt8] { Array("OHAI".utf8) }

    let port: any BootloaderPort
    let clock: C
    /// Received bytes not read yet (`SerialBufferedReader`).
    private var pending: [UInt8] = []
    private var isStub = false

    init(port: any BootloaderPort, clock: C) {
        self.port = port
        self.clock = clock
    }

    // MARK: Lines and baud rate

    func setBaudRate(_ rate: Int) async throws(FlashError) {
        do throws(TransportError) { try await port.setBaudRate(rate) } catch { throw .port(error) }
    }

    /// `enterBootLoader`: `IO0` low while `EN` pulses.
    func enterBootloader() async throws(FlashError) {
        try await pulse(idle: (true, false))
    }

    /// `reset`: `EN` pulses with `IO0` high, so the new firmware starts.
    func reset() async throws(FlashError) {
        try await pulse(idle: (false, false))
    }

    /// `idle`, then `EN` low (RTS) for 100 ms, then `idle` again 100 ms later.
    private func pulse(idle: (dtr: Bool, rts: Bool)) async throws(FlashError) {
        let steps: [(dtr: Bool, rts: Bool)] = [idle, (false, true), idle]
        for (index, lines) in steps.enumerated() {
            if index > 0 {
                try? await clock.sleep(for: Self.resetDelay)
            }
            do throws(TransportError) {
                try await port.setModemLines(dtr: lines.dtr, rts: lines.rts)
            } catch {
                throw .port(error)
            }
        }
    }

    // MARK: Commands

    /// `sync`: up to 20 attempts, then the queued answers of earlier attempts are dropped.
    mutating func sync() async throws(FlashError) {
        let payload: [UInt8] = [0x07, 0x07, 0x12, 0x20] + [UInt8](repeating: 0x55, count: 28)
        for _ in 0..<Self.syncAttempts {
            try await send(Opcode.sync, payload)
            let answer = try await response(to: Opcode.sync, timeout: Self.shortTimeout)
            if answer?.status(stub: false).success == true {
                while try await response(to: Opcode.sync, timeout: Self.shortTimeout) != nil {}
                return
            }
        }
        throw .noAnswer
    }

    mutating func changeBaudRate(_ rate: Int) async throws(FlashError) {
        try await command(Opcode.changeBaudRate, .le(UInt32(rate), 0), timeout: Self.shortTimeout)
        try await setBaudRate(rate)
    }

    mutating func detectChip() async throws(FlashError) {
        let magic = try await command(Opcode.readReg, .le(Self.chipDetectRegister), timeout: Self.shortTimeout).value
        guard magic == Self.esp32Magic else { throw .unsupportedChip(magic) }
    }

    /// `loadStub`: text and data into RAM, then run it; it greets with "OHAI".
    mutating func loadStub(_ stub: FlasherStub) async throws(FlashError) {
        try await memWrite(Array(stub.text), at: stub.textStart)
        try await memWrite(Array(stub.data), at: stub.dataStart)
        try await command(Opcode.memEnd, .le(0, stub.entry), timeout: Self.shortTimeout)
        guard try await frame(timeout: Self.shortTimeout, where: { $0 == Self.stubGreeting }) != nil else {
            throw .stubNotStarted
        }
        isStub = true
    }

    private mutating func memWrite(_ image: [UInt8], at offset: UInt32) async throws(FlashError) {
        let blocks = image.chunked(Self.memBlockSize)
        try await command(
            Opcode.memBegin,
            .le(UInt32(image.count), UInt32(blocks.count), UInt32(Self.memBlockSize), offset),
            timeout: Self.timeout(perMB: 30_000, image.count)
        )
        for (sequence, block) in blocks.enumerated() {
            try await command(
                Opcode.memData,
                .le(UInt32(block.count), UInt32(sequence), 0, 0) + block,
                checksum: Self.checksum(block),
                timeout: Self.timeout(perMB: 30_000, Self.memBlockSize)
            )
        }
    }

    /// `flashWrite` (blocks padded with zeros) or, compressed, `flashDeflWrite`; `progress` gets 0…100 per block.
    mutating func write(
        _ image: [UInt8],
        at offset: UInt32,
        compressed: Bool,
        progress: (Float) -> Void
    ) async throws(FlashError) {
        let payload = compressed ? Self.deflate(image) : image
        let blocks = payload.chunked(Self.flashBlockSize).map { block in
            compressed ? block : block + [UInt8](repeating: 0, count: Self.flashBlockSize - block.count)
        }
        try await command(
            compressed ? Opcode.flashDeflBegin : Opcode.flashBegin,
            .le(UInt32(image.count), UInt32(blocks.count), UInt32(Self.flashBlockSize), offset),
            timeout: Self.timeout(perMB: 30_000, image.count)
        )
        for (sequence, block) in blocks.enumerated() {
            progress(Float(sequence) * 100 / Float(blocks.count))
            try await command(
                compressed ? Opcode.flashDeflData : Opcode.flashData,
                .le(UInt32(block.count), UInt32(sequence), 0, 0) + block,
                checksum: Self.checksum(block),
                timeout: Self.timeout(perMB: 30_000, Self.flashBlockSize)
            )
        }
        progress(100)
    }

    /// `flashMd5Verify`: the stub answers the MD5 of the flash as 16 bytes.
    mutating func verify(_ image: [UInt8], at offset: UInt32) async throws(FlashError) {
        let response = try await command(
            Opcode.spiFlashMD5,
            .le(offset, UInt32(image.count), 0, 0),
            timeout: Self.timeout(perMB: 8000, image.count)
        )
        guard response.data.prefix(16).elementsEqual(Insecure.MD5.hash(data: image)) else {
            throw .verifyFailed(offset: offset)
        }
    }

    // MARK: Packets

    /// `exchange`: sends the command and waits for its response, which must report success.
    @discardableResult
    private mutating func command(
        _ opcode: UInt8,
        _ payload: [UInt8],
        checksum: UInt32 = 0,
        timeout: Duration
    ) async throws(FlashError) -> Response {
        try await send(opcode, payload, checksum: checksum)
        guard let response = try await response(to: opcode, timeout: timeout) else {
            throw .timeout(opcode: opcode)
        }
        let status = response.status(stub: isStub)
        guard status.success else { throw .commandFailed(opcode: opcode, error: status.error) }
        return response
    }

    /// `CommandPacket`: direction 0, opcode, length, checksum, payload; SLIP framed.
    private func send(_ opcode: UInt8, _ payload: [UInt8], checksum: UInt32 = 0) async throws(FlashError) {
        let header: [UInt8] = [0x00, opcode, UInt8(payload.count & 0xFF), UInt8(payload.count >> 8)]
        let packet = header + .le(checksum) + payload
        do throws(TransportError) { try await port.write([KISS.fend] + KISS.escape(packet) + [KISS.fend]) } catch {
            throw .port(error)
        }
    }

    private mutating func response(to opcode: UInt8, timeout: Duration) async throws(FlashError) -> Response? {
        try await frame(timeout: timeout) { Response($0)?.opcode == opcode }.flatMap(Response.init)
    }

    /// `waitForResponse`: the first SLIP frame `accept`s within `timeout`; other frames are dropped.
    private mutating func frame(
        timeout: Duration,
        where accept: ([UInt8]) -> Bool
    ) async throws(FlashError) -> [UInt8]? {
        let deadline = clock.now.advanced(by: timeout)
        var reader = SLIPReader()
        while clock.now < deadline {
            if pending.isEmpty {
                do { pending = try await port.read(timeout: clock.now.duration(to: deadline)) } catch {
                    throw .port(error)
                }
            }
            for (index, byte) in pending.enumerated() {
                if let frame = reader.read(byte), accept(frame) {
                    pending.removeFirst(index + 1)
                    return frame
                }
            }
            pending = []
        }
        return nil
    }

    // MARK: Helpers

    /// `timeoutPerMb`: at least 3 s.
    static func timeout(perMB milliseconds: Int, _ size: Int) -> Duration {
        .milliseconds(max(Int(Double(milliseconds) * Double(size) / 1_000_000), 3000))
    }

    /// `calcChecksum`.
    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        UInt32(bytes.reduce(0xEF, ^))
    }

    /// `compressBytes`: zlib at the best compression, like `java.util.zip.Deflater`.
    static func deflate(_ bytes: [UInt8]) -> [UInt8] {
        var size = compressBound(uLong(bytes.count))
        var output = [UInt8](repeating: 0, count: Int(size))
        _ = compress2(&output, &size, bytes, uLong(bytes.count), Z_BEST_COMPRESSION)
        return Array(output.prefix(Int(size)))
    }
}

/// `ResponsePacket`: direction 1, opcode, length, value, data ending in the status.
struct Response {
    let opcode: UInt8
    let value: UInt32
    let data: [UInt8]

    init?(_ frame: [UInt8]) {
        guard frame.count >= 8 else { return nil }
        let size = Int(frame[2]) | Int(frame[3]) << 8
        guard frame.count >= 8 + size else { return nil }
        opcode = frame[1]
        value = frame[4..<8].reversed().reduce(0) { $0 << 8 | UInt32($1) }
        data = Array(frame[8..<8 + size])
    }

    /// The stub ends with one status byte (0 = success, else the error); the ROM with four (status, error, 0, 0).
    func status(stub: Bool) -> (success: Bool, error: UInt8) {
        let status = stub ? data.suffix(1) : data.suffix(4).prefix(2)
        return (status.first == 0, status.last ?? 0xFF)
    }
}

/// Collects SLIP frames like `waitForResponse`: `0xC0` starts a frame and the next `0xC0` ends it; an unknown escape
/// stands for itself.
struct SLIPReader {
    private var frame: [UInt8] = []
    private var isInFrame = false
    private var isEscaped = false

    mutating func read(_ byte: UInt8) -> [UInt8]? {
        if byte == KISS.fend {
            defer { (frame, isEscaped) = ([], false) }
            isInFrame.toggle()
            return isInFrame ? nil : frame
        }
        guard isInFrame else { return nil }
        if isEscaped {
            frame.append(byte == KISS.tfend ? KISS.fend : byte == KISS.tfesc ? KISS.fesc : byte)
            isEscaped = false
        } else if byte == KISS.fesc {
            isEscaped = true
        } else {
            frame.append(byte)
        }
        return nil
    }
}

extension [UInt8] {
    /// Little-endian 32-bit words.
    static func le(_ words: UInt32...) -> [UInt8] {
        words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> (8 * $0)) } }
    }

    func chunked(_ size: Int) -> [[UInt8]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
