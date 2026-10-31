import Foundation
import Testing

@testable import KV4PTestSupport

@Suite("Vector file")
struct VectorFileTests {
    @Test("a missing file is reported by name")
    func missing() {
        #expect(throws: VectorFileError.missing("absent")) {
            try VectorFile<String, String>.load("absent", from: .main)
        }
    }

    @Test("hex decoding")
    func hex() throws {
        #expect(try [UInt8](hex: "c0db00") == [0xC0, 0xDB, 0x00])
        #expect(throws: VectorFileError.invalidHex("c")) { try [UInt8](hex: "c") }
        #expect(throws: VectorFileError.invalidHex("zz")) { try [UInt8](hex: "zz") }
    }
}
