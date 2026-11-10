import Foundation
import KV4PPersistence
import KV4PProtocol

/// Turns the CSV export of the DARC repeater lists (relaislisten.darc.de) into channel memories (ADR-0065).
public enum DARCImport {
    private static let header = "Call;QRG;Input"
    private static let separator: Character = ";"

    /// The columns by their place; the export misspells a name now and then, as "Länge" with a Cyrillic letter.
    private enum Column: Int {
        case call, qrg, input, locator, info, latitude, longitude, ctcss, mode
    }

    /// The new memories of `group` from a list, and those it completes; `nil` if the file is not one. New repeaters
    /// get `accessTone`.
    public static func preview(
        fromCSV text: String,
        group: String,
        existing: [ChannelMemory],
        accessTone: ImportAccessTone? = nil
    ) -> RepeaterImportPreview? {
        guard let (all, otherModes) = memories(fromCSV: text, group: group) else { return nil }
        return RepeaterImport.preview(
            all,
            otherModes: otherModes,
            group: group,
            existing: existing,
            accessTone: accessTone
        )
    }

    /// The FM repeaters and the beacons as memories of `group`, and how many entries have another mode; `nil` if the
    /// file is not a DARC list.
    public static func memories(fromCSV text: String, group: String) -> (memories: [ChannelMemory], otherModes: Int)? {
        let records = RepeaterImport.records(text)
        guard let header = records.first else { return ([], 0) }
        guard header.hasPrefix(Self.header) else { return nil }
        var otherModes = 0
        let memories = records.dropFirst().compactMap { record -> ChannelMemory? in
            let values = RepeaterImport.columns(record, separator: separator)
            let column = { (column: Column) in values.indices.contains(column.rawValue) ? values[column.rawValue] : "" }
            guard values.count >= 3, let frequency = number(column(.qrg)) else { return nil }
            guard isFM(column(.mode)) else {
                otherModes += 1
                return nil
            }
            var memory = ChannelMemory(
                name: column(.call),
                frequency: Float(frequency),
                offset: .none,
                offsetKHz: 0,
                txTone: CTCSS.normalize(number(column(.ctcss)).map { String($0) } ?? ""),
                group: group,
                kind: .repeater,
                comment: column(.info),
                latitude: degrees(column(.latitude)),
                longitude: degrees(column(.longitude))
            )
            let input = column(.input)
            if input.caseInsensitiveCompare("Beacon") == .orderedSame {
                memory.kind = .beacon
            } else if let input = number(input) {
                let kHz = Int(((input - frequency) * 1000).rounded())
                memory.offset = kHz < 0 ? .down : kHz > 0 ? .up : .none
                memory.offsetKHz = abs(kHz)
            }
            return memory
        }
        return (memories, otherModes)
    }

    /// An entry without a mode is FM, as is one that names FM among others, such as "FM/DMR"; "C4FM" is not.
    private static func isFM(_ mode: String) -> Bool {
        mode.isEmpty || mode.uppercased().split { !$0.isLetter && !$0.isNumber }.contains("FM")
    }

    /// A number with a decimal comma or point, and maybe a unit after it, as in "88,5Hz".
    private static func number(_ text: String) -> Double? {
        Double(text.replacing(",", with: ".").prefix { $0.isNumber || $0 == "." || $0 == "-" })
    }

    /// Degrees and minutes, maybe seconds, and the hemisphere, as in `52°31'N`, or a decimal; south and west negative.
    static func degrees(_ text: String) -> Double? {
        guard let hemisphere = text.last, "NSEOW".contains(hemisphere) else { return number(text) }
        let parts = text.dropLast().split { !$0.isNumber }.compactMap { Double($0) }
        guard (1...3).contains(parts.count) else { return nil }
        let value = zip(parts, [1.0, 60, 3600]).reduce(0) { $0 + $1.0 / $1.1 }
        return "SW".contains(hemisphere) ? -value : value
    }
}
