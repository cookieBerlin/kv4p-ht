import Foundation

/// The radio that sent a Mic-E packet, which marks itself by bytes around the comment (ADR-0054). The list comes from
/// the APRS device identification database (CC BY-SA 2.0, https://github.com/aprsorg/aprs-deviceid).
struct MicEDevice: Equatable, Sendable {
    /// The whole mark at the end of the comment.
    let mark: String
    let name: String

    /// Marks at the end of a comment, after the prefix `` ` `` (with messaging) or `'`.
    private static let suffixes = [
        "_ ": "Yaesu VX-8", "_\"": "Yaesu FTM-350", "_#": "Yaesu VX-8G", "_$": "Yaesu FT1D", "_(": "Yaesu FT2D",
        "_0": "Yaesu FT3D", "_3": "Yaesu FT5D", "_1": "Yaesu FTM-300D", "_2": "Yaesu FTM-200D", "_4": "Yaesu FTM-500D",
        "_5": "Yaesu FTM-510D", "_6": "Yaesu FTX-1", "_7": "Yaesu FTM-310D", "_)": "Yaesu FTM-100D",
        "_%": "Yaesu FTM-400DR", "(5": "Anytone D578UV", "(8": "Anytone D878UV", "|3": "Byonics TinyTrak3",
        "|4": "Byonics TinyTrak4", "^A": "AxelStack LLC APRS Connect", "^v": "HinzTec anyfrog", "*v": "KissOZ Tracker",
        "*9": "NOR AVRT9", ":2": "SQ8L VP-Tracker", " X": "SainSonic AP510", "[1": "Open Source APRSdroid",
    ]
    /// Radios known by their prefix, with a name for the mark at the end of a comment.
    private static let prefixes: [UInt8: (plain: String, marked: [Character: String])] = [
        UInt8(ascii: ">"): (
            "Kenwood TH-D7A", ["=": "Kenwood TH-D72", "^": "Kenwood TH-D74", "&": "Kenwood TH-D75"]
        ),
        UInt8(ascii: "]"): ("Kenwood TM-D700", ["=": "Kenwood TM-D710"]),
    ]
    /// The byte after the data type, the position and the symbol.
    private static let prefixOffset = 9

    /// The device of the information field of a Mic-E packet, if it is a known one.
    init?(payload: [UInt8]) {
        guard payload.count > Self.prefixOffset else { return nil }
        let prefix = payload[Self.prefixOffset]
        let comment = Java.utf8(payload[(Self.prefixOffset + 1)...])
        if let models = Self.prefixes[prefix] {
            if let last = comment.last, let name = models.marked[last] {
                mark = String(last)
                self.name = name
            } else {
                mark = ""
                name = models.plain
            }
            return
        }
        let mark = String(comment.suffix(2))
        guard [UInt8(ascii: "`"), UInt8(ascii: "'")].contains(prefix), let name = Self.suffixes[mark] else {
            return nil
        }
        self.mark = mark
        self.name = name
    }

    /// The comment without the mark; `nil` if nothing else was in it.
    func commentWithoutMark(_ comment: String?) -> String? {
        let text = (comment ?? "").trimmingCharacters(in: .whitespaces)
        let rest =
            text.hasSuffix(mark.trimmingCharacters(in: .whitespaces))
            ? text.dropLast(mark.trimmingCharacters(in: .whitespaces).count) : Substring(text)
        let trimmed = rest.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
