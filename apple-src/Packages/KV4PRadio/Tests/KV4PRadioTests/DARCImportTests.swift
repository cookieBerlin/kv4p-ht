import Foundation
import KV4PPersistence
import Testing

@testable import KV4PRadio

/// The CSV export of the DARC repeater lists (relaislisten.darc.de), with placeholder data (ADR-0065).
@Suite("DARC import")
struct DARCImportTests {
    static let vhf: ClosedRange<Float> = 134...174

    static let list = """
        Call;QRG;Input;Locator;Info;Breite;Länge;CTCSS;Mode/Node;Entfernung zu AA00AA\r
        N0CALL;145,600;145,000;AA00AA;Example repeater;12°30'N;45°15'W;88,5Hz;;12,3\r
        N1CALL;439,1625;431,5625;AA00AA;;12°00'S;045°30'E;;FM;1,0\r
        N2CALL;144,480;Beacon;AA00AA;Example beacon;1°06'N;2°12'E;;;2,0\r
        N3CALL;145,500;;AA00AA;;;;;;\r
        N4CALL;145,7375;145,1375;AA00AA;;;;;DMR;\r
        N5CALL;145,650;146.250;AA00AA;;;;67,0Hz;FM/DMR;\r
        N6CALL;145,675;145;AA00AA;;;;;C4FM;\r
        N7CALL;1296,900;Beacon;AA00AA;;;;;;\r
        N8CALL;bad;145,000;AA00AA;;;;;;\r
        N9CALL;145\r
        N10CALL;145,525;145,525\r
        \r

        """

    @Test("FM repeaters and beacons: name, frequency, offset, tone, comment and position")
    func entries() throws {
        let parsed = try #require(DARCImport.memories(fromCSV: Self.list, group: "Local"))
        let memories = parsed.memories
        #expect(memories.map(\.name) == ["N0CALL", "N1CALL", "N2CALL", "N3CALL", "N5CALL", "N7CALL", "N10CALL"])
        #expect(parsed.otherModes == 2)
        #expect(memories.map(\.frequency) == [145.6, 439.1625, 144.48, 145.5, 145.65, 1296.9, 145.525])
        #expect(memories.map(\.kind) == [.repeater, .repeater, .beacon, .repeater, .repeater, .beacon, .repeater])
        #expect(memories.map(\.offset) == [.down, .down, .none, .none, .up, .none, .none])
        #expect(memories.map(\.offsetKHz) == [600, 7600, 0, 0, 600, 0, 0])
        #expect(memories.map(\.txTone) == ["88.5", "None", "None", "None", "67", "None", "None"])
        #expect(memories.map(\.comment) == ["Example repeater", "", "Example beacon", "", "", "", ""])
        #expect(memories.map(\.latitude) == [12.5, -12, 1 + 6 / 60.0, nil, nil, nil, nil])
        #expect(memories.map(\.longitude) == [-45.25, 45.5, 2 + 12 / 60.0, nil, nil, nil, nil])
        #expect(memories.allSatisfy { $0.group == "Local" && $0.rxTone == "None" && $0.id == 0 })
    }

    @Test("the preview leaves out other modes, what the radio cannot receive and what the group has")
    func preview() throws {
        let existing = [ChannelMemory(name: "N3CALL", frequency: 145.5, group: "Local")]
        let preview = try #require(
            DARCImport.preview(fromCSV: Self.list, group: "Local", range: Self.vhf, existing: existing)
        )
        #expect(preview.memories.map(\.name) == ["N0CALL", "N2CALL", "N5CALL", "N10CALL"])
        #expect(preview.otherModes == 2)
        #expect(preview.outOfRange == 2)
        #expect(preview.duplicates == 1)
        #expect(
            preview.summary
                == "3 repeaters and 1 beacon to import. "
                + "Left out: 2 of another mode, 2 outside the radio's range, 1 already in this group."
        )
    }

    @Test("a file that is not a DARC list is refused, an empty one has nothing")
    func unknown() {
        #expect(DARCImport.memories(fromCSV: "Freq,Input,Offset,Tone,Location\n146.52", group: "") == nil)
        #expect(DARCImport.memories(fromCSV: "", group: "")?.memories == [])
        // A list with only the first columns: no mode is FM.
        let short = DARCImport.memories(fromCSV: "Call;QRG;Input\nN0CALL;145,600;145,000", group: "")
        #expect(short?.memories.map(\.offset) == [.down])
        #expect(DARCImport.preview(fromCSV: "Name;QRG", group: "", range: Self.vhf, existing: []) == nil)
    }

    @Test("the columns are found by their place, as the export may spell a name wrongly")
    func brokenHeader() throws {
        let list = "Call;QRG;Input;Locator;Info;Breite;L\u{0444}nge;CTCSS;Mode/Node;Entfernung zu AA00AA\n"
            + "N0CALL;145,600;145,000;AA00AA;;12°30'N;45°15'W;;;\n"
        let memory = try #require(DARCImport.memories(fromCSV: list, group: "")?.memories.first)
        #expect(memory.latitude == 12.5)
        #expect(memory.longitude == -45.25)
    }

    @Test("degrees and minutes, with seconds or as a decimal, become decimal degrees")
    func degrees() {
        #expect(DARCImport.degrees("52°31'N") == 52 + 31 / 60.0)
        #expect(DARCImport.degrees("13°24'30\"E") == 13 + 24 / 60.0 + 30 / 3600.0)
        #expect(DARCImport.degrees("13°24'O") == 13 + 24 / 60.0)
        #expect(DARCImport.degrees("1°30'W") == -1.5)
        #expect(DARCImport.degrees("12,5") == 12.5)
        #expect(DARCImport.degrees("-12.5") == -12.5)
        #expect(DARCImport.degrees("") == nil)
        #expect(DARCImport.degrees("north") == nil)
        #expect(DARCImport.degrees("1°2'3\"4'N") == nil)
    }
}

/// What both imports share (ADR-0065).
@Suite("Repeater import")
struct RepeaterImportTests {
    @Test("a file is read as UTF-8, otherwise as Windows-1252, and without a byte order mark")
    func text() throws {
        let utf8 = Data("Call;Länge\n".utf8)
        #expect(RepeaterImport.text(from: utf8) == "Call;Länge\n")
        #expect(RepeaterImport.text(from: Data([0xEF, 0xBB, 0xBF]) + utf8) == "Call;Länge\n")
        let windows = try #require("Call;Länge\n".data(using: .windowsCP1252))
        #expect(RepeaterImport.text(from: windows) == "Call;Länge\n")
        // Windows-1252 leaves five bytes unassigned.
        #expect(RepeaterImport.text(from: Data([0x41, 0x81, 0xE4])) == "A\u{FFFD}ä")
    }

    @Test("a DARC list in Windows-1252 is read")
    func windowsList() throws {
        let data = try #require(DARCImportTests.list.data(using: .windowsCP1252))
        let text = RepeaterImport.text(from: data)
        #expect(DARCImport.memories(fromCSV: text, group: "")?.memories.count == 7)
    }

    @Test("the summary names repeaters and beacons, and leaves out what is not there")
    func summary() {
        let repeater = ChannelMemory(name: "R", frequency: 145, kind: .repeater)
        let beacon = ChannelMemory(name: "B", frequency: 144, kind: .beacon)
        let preview = { (memories: [ChannelMemory]) in
            RepeaterImportPreview(memories: memories, outOfRange: 0, duplicates: 0, otherModes: 1)
        }
        #expect(preview([repeater]).summary == "1 repeater to import. Left out: 1 of another mode.")
        #expect(preview([beacon, beacon]).summary == "2 beacons to import. Left out: 1 of another mode.")
        #expect(preview([repeater, repeater]).imported == "2 repeaters")
        #expect(preview([repeater, beacon]).imported == "1 repeater and 1 beacon")
    }
}
