import Foundation
import KV4PProtocol
import KV4PTestSupport
import KV4PTransport
import Testing

@testable import KV4PFlasher

/// esp32-flash-lib's failures, by changing one answer of the recorded flash. Writes of the recording: 0 SYNC,
/// 1 CHANGE_BAUDRATE, 2 READ_REG, 3–6 MEM_BEGIN/MEM_DATA, 7 MEM_END, 8 FLASH_BEGIN, 9 FLASH_DATA, 10 SPI_FLASH_MD5.
@Suite("Flasher errors")
struct FlasherErrorTests {
    /// A SLIP-framed response: direction 1, opcode, length, value, data, status.
    static func reply(_ opcode: UInt8, value: UInt32 = 0, data: [UInt8] = [], status: [UInt8]) -> [UInt8] {
        let body = data + status
        let length = UInt16(body.count)
        let packet =
            [0x01, opcode, UInt8(length & 0xFF), UInt8(length >> 8)]
            + (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) } + body
        return [KISS.fend] + KISS.escape(packet) + [KISS.fend]
    }

    static let romOK: [UInt8] = [0, 0, 0, 0]

    func flash(replacing overrides: [Int: [UInt8]] = [:], failure: TranscriptPort.Failure? = nil) async throws
        -> FlashError?
    {
        let vector = try FlasherVectorTests.vector("flash")
        let clock = VirtualClock()
        let port = TranscriptPort(
            transcript: vector.expected.transcript,
            replacing: overrides,
            clock: clock,
            failure: failure
        )
        return try await FlasherVectorTests.flash(vector, into: port, clock: clock)
    }

    @Test("a chip other than the ESP32 is refused")
    func otherChip() async throws {
        #expect(
            try await flash(replacing: [2: Self.reply(0x0A, value: 0x9, status: Self.romOK)]) == .unsupportedChip(0x9)
        )
    }

    @Test("a failed ROM command reports its error code")
    func romError() async throws {
        let failed = Self.reply(0x0F, status: [1, 5, 0, 0])
        #expect(try await flash(replacing: [1: failed]) == .commandFailed(opcode: 0x0F, error: 5))
    }

    @Test("a failed stub command reports its error code")
    func stubError() async throws {
        let failed = Self.reply(0x03, status: [1, 0xC1])
        #expect(try await flash(replacing: [9: failed]) == .commandFailed(opcode: 0x03, error: 0xC1))
    }

    @Test("a command without an answer times out")
    func timeout() async throws {
        #expect(try await flash(replacing: [8: []]) == .timeout(opcode: 0x02))
    }

    @Test("a stub that does not say OHAI has not started")
    func stubSilent() async throws {
        #expect(try await flash(replacing: [7: Self.reply(0x06, status: Self.romOK)]) == .stubNotStarted)
    }

    @Test("a failing port ends the flash", arguments: TranscriptPort.Failure.allCases)
    func portFailure(failure: TranscriptPort.Failure) async throws {
        #expect(try await flash(failure: failure) == .port(.ioFailed(errno: 5)))
    }

    @Test("noise, short frames, other opcodes and invalid escapes are skipped like esp32-flash-lib")
    func robustReader() async throws {
        let sync = Self.reply(0x08, data: [0xDB, 0x41], status: Self.romOK)
        let noise: [UInt8] = [0x55, 0xC0, 0x01, 0x02, 0xC0] + Self.reply(0x0A, status: Self.romOK)
        #expect(try await flash(replacing: [0: noise + sync]) == nil)
    }

    @Test("an invalid stub is an error")
    func invalidStub() {
        #expect(throws: (any Error).self) { try FlasherStub.decode(Data()) }
    }

    @Test("a response without status bytes counts as failed")
    func noStatus() async throws {
        #expect(
            try await flash(replacing: [1: Self.reply(0x0F, status: [])]) == .commandFailed(opcode: 0x0F, error: 0xFF)
        )
    }

    @Test("the stub is esptool's ESP32 flasher stub")
    func stub() throws {
        let stub = try FlasherStub.esp32()
        #expect(stub.text.count == 3532)
        #expect(stub.data.count == 156)
        #expect(stub.textStart == 0x400B_E000)
        #expect(stub.dataStart == 0x3FFD_EBA8)
        #expect(stub.entry == 0x400B_E5EC)
    }
}
