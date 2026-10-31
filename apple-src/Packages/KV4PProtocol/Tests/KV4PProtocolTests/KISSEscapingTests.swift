import Testing

@testable import KV4PProtocol

@Suite("KISS escaping")
struct KISSEscapingTests {
    @Test("plain bytes pass through unchanged")
    func plainBytes() {
        #expect(KISS.escape([0x00, 0x01, 0x7F, 0xFF]) == [0x00, 0x01, 0x7F, 0xFF])
    }

    @Test("FEND is escaped as FESC TFEND")
    func fend() {
        #expect(KISS.escape([0xC0]) == [0xDB, 0xDC])
    }

    @Test("FESC is escaped as FESC TFESC")
    func fesc() {
        #expect(KISS.escape([0xDB]) == [0xDB, 0xDD])
    }

    @Test("mixed payload escapes every special byte")
    func mixed() {
        #expect(KISS.escape([0x01, 0xC0, 0x02, 0xDB, 0x03]) == [0x01, 0xDB, 0xDC, 0x02, 0xDB, 0xDD, 0x03])
    }

    @Test("empty payload stays empty")
    func empty() {
        #expect(KISS.escape([]) == [])
    }
}
