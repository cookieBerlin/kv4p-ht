import Foundation
import Testing

@testable import KV4PAPRS

/// The export of the APRS list as CSV and as raw packets (ADR-0057).
@Suite("APRS export")
struct APRSExportTests {
    private static func event(_ line: String, atMs ms: Int64 = 1_000) -> APRSEvent {
        var controller = APRSController(startMs: 0)
        controller.callsign = "N0CALL"
        _ = controller.receive(internetLine: line, atMs: ms)
        return controller.events[0]
    }

    @Test("CSV has a header and one line per packet, oldest as given")
    func csv() {
        let position = Self.event("N1CALL>APRS:=4903.50N/07201.75W>Hello", atMs: 1_000)
        let message = Self.event("N1CALL>APRS::N0CALL   :Hi there", atMs: 2_000)
        let lines = APRSExport.csv([position, message]).components(separatedBy: "\r\n")
        #expect(lines[0] == "Time,From,To,Type,Latitude,Longitude,Symbol,Device,Text,Internet only,Packet")
        #expect(lines[1].hasPrefix("1970-01-01T00:00:01Z,N1CALL,,Position,49.05833,-72.02917,/>,,Hello,yes,"))
        #expect(lines[2].hasPrefix("1970-01-01T00:00:02Z,N1CALL,N0CALL,Message,,,,,Hi there,yes,"))
        #expect(lines[3].isEmpty)
    }

    @Test("a value with a comma, a quote or a line break is quoted")
    func quoting() {
        #expect(APRSExport.field("a,b") == "\"a,b\"")
        #expect(APRSExport.field("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(APRSExport.field("one\ntwo") == "\"one\ntwo\"")
        #expect(APRSExport.field("plain") == "plain")
    }

    @Test(
        "text from the air cannot become a formula in a spreadsheet",
        arguments: ["=1+1", "+1", "-1", "@SUM(A1)", "\tx", "\rx"]
    )
    func formulas(text: String) {
        #expect(APRSExport.field(text).contains("'\(text.first ?? " ")"))
    }

    @Test("a repeater summary and weather read as in the list, in metric, whatever the device")
    func text() {
        let weather = Self.event("N1CALL>APRS:=4903.50N/07201.75W_220/004t077h50")
        #expect(APRSExport.csv([weather]).contains("\"25 °C · 50 %\nWind SW 6 km/h\""))
    }

    @Test("raw packets are one line each, and a packet without a line is left out")
    func raw() {
        let first = Self.event("N1CALL>APRS:>One")
        var second = Self.event("N2CALL>APRS:>Two")
        #expect(APRSExport.rawLines([first, second]) == "N1CALL>APRS:>One\nN2CALL>APRS:>Two\n")
        second.rawLine = nil
        #expect(APRSExport.rawLines([first, second]) == "N1CALL>APRS:>One\n")
    }

    @Test("the formats name their file and say what they are")
    func formats() {
        #expect(APRSExport.Format.csv.fileName == "aprs-packets.csv")
        #expect(APRSExport.Format.raw.fileName == "aprs-packets.txt")
        #expect(!APRSExport.Format.csv.label.isEmpty)
        #expect(!APRSExport.Format.raw.label.isEmpty)
        #expect(Self.text(.csv).hasPrefix("Time,"))
        #expect(Self.text(.raw) == "N1CALL>APRS:>One\n")
    }

    private static func text(_ format: APRSExport.Format) -> String {
        format.text(of: [event("N1CALL>APRS:>One")])
    }
}
