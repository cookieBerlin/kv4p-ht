import Testing

@testable import KV4PAPRS

/// The Java string semantics the port depends on.
@Suite("Java text")
struct JavaTextTests {
    @Test("split drops trailing empty strings like String.split")
    func split() {
        #expect(Java.split("a,,b,,", ",") == ["a", "", "b"])
        #expect(Java.split(",,", ",") == [])
        #expect(Java.split("", ",") == [""])
        #expect(Java.split("abc", ",") == ["abc"])
    }

    @Test("ISO-8859-1 encoding replaces other characters with ?")
    func latin1Bytes() {
        #expect(Java.latin1Bytes("Aü€") == [0x41, 0xFC, 0x3F])
    }

    @Test("a TNC2 line with characters beyond Latin-1 parses like Java")
    func tnc2NonLatin1() throws {
        let packet = try APRSParser.parse(tnc2: "N0CALL>APRS:>status €")
        #expect(packet.info.status?.text == "status ?")
        #expect(throws: APRSParseError.invalidLine) { try APRSParser.parse(tnc2: "N0CALL>APRS:") }
        #expect(throws: APRSParseError.invalidLine) { try APRSParser.parse(tnc2: "N0CALL>APRS:@0923") }
    }
}
