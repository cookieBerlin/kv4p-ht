import Testing

@testable import KV4PAPRS

#if canImport(AppKit)
    import AppKit
#endif

/// What a received symbol means, and which radio sent a Mic-E packet (ADR-0054).
@Suite("APRS symbols and devices")
struct APRSSymbolInfoTests {
    private static func event(_ line: String) -> APRSEvent? {
        var controller = APRSController(startMs: 0)
        controller.callsign = "N1CALL"
        _ = controller.receive(internetLine: line, atMs: 1)
        return controller.events.first
    }

    private static let micE = "N0CALL-7>S32U6T,WIDE1-1:`(_fn\"Oj/"

    @Test("a symbol of the primary table has its meaning and icon")
    func primary() {
        let symbol = APRSSymbolInfo(table: "/", code: ">")
        #expect(symbol.name == "Car")
        #expect(symbol.icon == .character("🚗"))
        #expect(symbol.overlay == nil)
        #expect(symbol.codeText == "/>")
    }

    @Test("a symbol of the alternate table has its own meaning")
    func alternate() {
        #expect(APRSSymbolInfo(table: "\\", code: "s").name == "Ship, boat")
        #expect(APRSSymbolInfo(table: "\\", code: "s").overlay == nil)
    }

    @Test(
        "an overlay is a symbol of the alternate table, with a mark",
        arguments: [("D", "D"), ("7", "7"), ("a", "0"), ("j", "9")] as [(Character, Character)]
    )
    func overlay(table: Character, mark: Character) {
        let symbol = APRSSymbolInfo(table: table, code: "#")
        #expect(symbol.name == "Digipeater, green star")
        #expect(symbol.overlay == mark)
        #expect(symbol.codeText == "\(table)#")
    }

    @Test("an unused or strange code has no meaning, but still shows what arrived")
    func unknown() {
        #expect(APRSSymbolInfo(table: "/", code: "D").name == nil)
        #expect(APRSSymbolInfo(table: "/", code: "D").icon == nil)
        #expect(APRSSymbolInfo(table: "?", code: ">").name == nil)
        #expect(APRSSymbolInfo(table: "?", code: ">").overlay == nil)
    }

    @Test("every symbol of the table has a name and an icon that exists")
    func table() {
        #expect(APRSSymbolInfo.table.count > 140)
        for (key, entry) in APRSSymbolInfo.table {
            #expect(!entry.name.isEmpty, "\(key)")
            #expect(key.count == 2, "\(key)")
            switch entry.icon {
            case .character(let text):
                #expect(!text.isEmpty, "\(key)")
            case .system(let name):
                #if canImport(AppKit)
                    #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "\(name)")
                #endif
            }
        }
    }

    @Test("every symbol the app can send has a meaning and an icon", arguments: APRSSymbol.allCases)
    func ownSymbols(symbol: APRSSymbol) {
        let info = APRSSymbolInfo(table: "/", code: symbol.code)
        #expect(info.name != nil)
        #expect(symbol.icon == info.icon)
    }

    @Test("a beacon of the app comes back with its symbol, its place and nothing else", arguments: APRSSymbol.allCases)
    func ownBeacon(symbol: APRSSymbol) throws {
        for (latitude, longitude) in [(-89.5, -179.5), (-17.9, 81.6), (0.5, 0.5), (49.05, -72.03), (89.5, 179.5)] {
            let beacon = APRSBeacon(latitude: latitude, longitude: longitude, symbolTable: "/", symbolCode: symbol.code)
            let event = try #require(Self.event("N0CALL>APKVPA,TCPIP*:" + beacon.payload))
            #expect(event.kind == .position)
            #expect(event.symbol == APRSSymbolInfo(table: "/", code: symbol.code))
            #expect(abs(event.latitude - latitude) < 0.01)
            #expect(abs(event.longitude - longitude) < 0.01)
            #expect(event.comment == nil)
        }
    }

    @Test("objects and uncompressed positions have a symbol, a message has none")
    func kinds() {
        let object = Self.event("N1CALL>APRS:;TESTOBJ  *111111z4903.50N/07201.75W-Test object")
        #expect(object?.symbol?.name == "House")
        let position = Self.event("N1CALL>APRS:=4903.50N/07201.75W>Test")
        #expect(position?.symbol?.name == "Car")
        let message = Self.event("N1CALL>APRS::N0CALL   :Hello")
        #expect(message?.symbol == nil)
        let status = Self.event("N1CALL>APRS:>Test status")
        #expect(status?.symbol == nil)
    }

    @Test(
        "a Mic-E device mark becomes the name of the radio",
        arguments: [
            ("`_3", "Yaesu FT5D", nil),
            ("`Hello_3", "Yaesu FT5D", "Hello"),
            ("`_ ", "Yaesu VX-8", nil),
            ("`Hello_\"", "Yaesu FTM-350", "Hello"),
            ("'Trip|4", "Byonics TinyTrak4", "Trip"),
            ("`[1", "Open Source APRSdroid", nil),
            (">Hello=", "Kenwood TH-D72", "Hello"),
            (">Hello^", "Kenwood TH-D74", "Hello"),
            (">Hello&", "Kenwood TH-D75", "Hello"),
            (">Hello", "Kenwood TH-D7A", "Hello"),
            ("]Hello=", "Kenwood TM-D710", "Hello"),
            ("]Hello", "Kenwood TM-D700", "Hello"),
        ] as [(String, String, String?)]
    )
    func device(tail: String, device: String, comment: String?) {
        let event = Self.event(Self.micE + tail)
        #expect(event?.deviceName == device)
        #expect(event?.displayComment == comment)
    }

    @Test("the comment itself stays as the Android code gives it")
    func commentStays() {
        #expect(Self.event(Self.micE + "`_3")?.comment == "_3")
    }

    @Test(
        "without a known mark, the comment stays and no radio is named",
        arguments: [
            "`Hello", "`Hello_9", "'Hello=", "`=", "/Hello_3",
        ]
    )
    func noDevice(tail: String) {
        let event = Self.event(Self.micE + tail)
        #expect(event?.deviceName == nil)
        #expect(event?.displayComment == event?.comment)
    }

    @Test("a Mic-E packet that ends after its position has no device and no comment")
    func noTail() {
        let event = Self.event(Self.micE)
        #expect(event?.deviceName == nil)
        #expect(event?.displayComment == nil)
    }

    @Test("a normal comment that looks like a mark stays what it is")
    func notMicE() {
        let event = Self.event("N1CALL>APRS:=4903.50N/07201.75W>Hello_3")
        #expect(event?.deviceName == nil)
        #expect(event?.displayComment == "Hello_3")
    }

    @Test("the details name all that is known")
    func details() throws {
        let full = try #require(Self.event("N0CALL-7>S32U6T,WIDE1-1:`(_fn\"OjD`Hello_3"))
        #expect(
            full.symbolDetails == [
                "Work zone, excavating machine", "Code: Dj", "Overlay: D", "Device: Yaesu FT5D",
            ]
        )
        let plain = try #require(Self.event("N1CALL>APRS:=4903.50N/07201.75W>Hello"))
        #expect(plain.symbolDetails == ["Car", "Code: />"])
        let message = try #require(Self.event("N1CALL>APRS::N0CALL   :Hello"))
        #expect(message.symbolDetails.isEmpty)
    }
}
