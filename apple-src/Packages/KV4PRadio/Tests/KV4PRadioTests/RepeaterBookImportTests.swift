import KV4PPersistence
import Testing

@testable import KV4PRadio

/// `FindRepeatersActivity.parseRepeaterList` and `findRepeatersSaveButtonClicked`, with placeholder data.
@Suite("RepeaterBook import")
struct RepeaterBookImportTests {
    static let vhf: ClosedRange<Float> = 134...174

    static let us = """
        Freq,Input,Offset,Tone,Location,State,County,Call,Use,Miles,Bearing,Degrees\r
        146.94000,146.34000,-0.6,100.0,"Example City, North",XX,Example,N0CALL,OPEN,3.2,N,10\r
        147.12000,147.72000,+0.6,,Sample Town,XX,Sample,N1CALL,OPEN,5.0,E,90\r
        146.52000,146.52000,0,123,"Line
        Break",XX,Sample,N2CALL,OPEN,7.1,S,180\r
        442.10000,447.10000,+5,88.5,Far Away,XX,Far,N3CALL,OPEN,9,W,270\r
        146.70000,short\r
        \r

        """

    static let international = """
        Output Freq,Input Freq,Offset,Uplink Tone,Downlink Tone,Call,Location,Region,Country,Use,Modes
        145.6000,145.0000,-0.6000,71.9,,N0CALL,Example Village,Region,XX,OPEN,FM
        145.5000,145.5000,0,,,N1CALL,Other Place,Region,XX,OPEN,FM
        bad,145.0,-0.6,77,,N2CALL,Nowhere,Region,XX,OPEN,FM
        145.2000,145.2000,n/a,,,N3CALL,Unknown Offset,Region,XX,OPEN,FM
        """

    @Test("US format: offset sign and size, tone, name, quotes and line breaks")
    func usFormat() throws {
        let memories = try #require(RepeaterBookImport.memories(fromCSV: Self.us, group: "Local", range: Self.vhf))
        #expect(memories.map(\.name) == ["N0CALL • Example City, North", "N1CALL • Sample Town", "N2CALL • Line Break"])
        #expect(memories.map(\.frequency) == [146.94, 147.12, 146.52])
        #expect(memories.map(\.offset) == [.down, .up, .none])
        #expect(memories.map(\.offsetKHz) == [600, 600, 0])
        #expect(memories.map(\.txTone) == ["100", "None", "123"])
        #expect(memories.allSatisfy { $0.rxTone == "None" && $0.group == "Local" && !$0.skipDuringScan && $0.id == 0 })
    }

    @Test("international format")
    func internationalFormat() throws {
        let memories = try #require(
            RepeaterBookImport.memories(fromCSV: Self.international, group: "", range: Self.vhf)
        )
        #expect(
            memories.map(\.name) == ["N0CALL • Example Village", "N1CALL • Other Place", "N3CALL • Unknown Offset"]
        )
        #expect(memories.map(\.offset) == [.down, .none, .none])
        #expect(memories.first?.txTone == "71.9")
    }

    @Test("an unknown file is refused, an empty one has no repeaters")
    func unknown() {
        #expect(RepeaterBookImport.memories(fromCSV: "Name,Frequency\nA,146.52", group: "", range: Self.vhf) == nil)
        #expect(RepeaterBookImport.memories(fromCSV: "", group: "", range: Self.vhf) == [])
    }
}
