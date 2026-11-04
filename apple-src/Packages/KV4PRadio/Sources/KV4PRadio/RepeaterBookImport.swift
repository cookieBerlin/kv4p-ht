import Foundation
import KV4PPersistence
import KV4PProtocol

/// What importing a RepeaterBook CSV export would do.
public struct RepeaterBookPreview: Equatable, Sendable {
    /// The new memories.
    public let memories: [ChannelMemory]
    /// Repeaters the radio cannot receive.
    public let outOfRange: Int
    /// Repeaters the group already has, or that the file lists twice.
    public let duplicates: Int

    public var summary: String {
        let count = "\(memories.count) repeater\(memories.count == 1 ? "" : "s") to import."
        var leftOut: [String] = []
        if outOfRange > 0 { leftOut.append("\(outOfRange) outside the radio's range") }
        if duplicates > 0 { leftOut.append("\(duplicates) already in this group") }
        return leftOut.isEmpty ? count : count + " Left out: " + leftOut.joined(separator: ", ") + "."
    }
}

/// Turns a RepeaterBook CSV export into channel memories (Android `FindRepeatersActivity.parseRepeaterList` and
/// `findRepeatersSaveButtonClicked`).
public enum RepeaterBookImport {
    private static let usHeader = "Freq,Input,Offset,Tone,Location"
    private static let internationalHeader = "Output Freq,Input Freq,Offset,Uplink Tone"

    /// The new memories of `group` from an export; `nil` if the file is not one. A repeater counts as present if `group`
    /// has a memory with the same name and frequency.
    public static func preview(
        fromCSV text: String,
        group: String,
        range: ClosedRange<Float>,
        existing: [ChannelMemory]
    ) -> RepeaterBookPreview? {
        guard let inRange = memories(fromCSV: text, group: group, range: range),
            let all = memories(fromCSV: text, group: group, range: -Float.infinity...Float.infinity)
        else { return nil }
        var seen = existing.filter { $0.group == group }.map(\.importKey)
        let new = inRange.filter { memory in
            guard !seen.contains(memory.importKey) else { return false }
            seen.append(memory.importKey)
            return true
        }
        return RepeaterBookPreview(
            memories: new,
            outOfRange: all.count - inRange.count,
            duplicates: inRange.count - new.count
        )
    }

    /// The repeaters within `range` as memories of `group`; `nil` if the file is not a RepeaterBook export.
    public static func memories(fromCSV text: String, group: String, range: ClosedRange<Float>) -> [ChannelMemory]? {
        // "\r\n" is one Character in Swift; Android reads lines without "\r".
        let records = records(text.replacing("\r\n", with: "\n").replacing("\r", with: ""))
        guard let header = records.first else { return [] }
        let isUS = header.hasPrefix(usHeader)
        guard isUS || header.hasPrefix(internationalHeader) else { return nil }
        return records.dropFirst()
            .filter { !$0.allSatisfy(\.isWhitespace) }
            .compactMap { record in
                let columns = columns(record)
                guard columns.count >= (isUS ? 12 : 11) else { return nil }
                let frequency = Double(columns[0]) ?? 0
                guard Double(range.lowerBound) <= frequency, frequency <= Double(range.upperBound) else { return nil }
                let offset = Double(columns[2]) ?? 0
                let call = columns[isUS ? 7 : 5]
                let location = columns[isUS ? 4 : 6].replacing("\n", with: " ")
                return ChannelMemory(
                    name: "\(call) • \(location)",
                    frequency: HamFrequency.safe(Float(frequency), in: range),
                    offset: offset < 0 ? .down : offset > 0 ? .up : .none,
                    offsetKHz: abs(Int(offset * 1000)),
                    txTone: CTCSS.normalize(columns[3]),
                    group: group
                )
            }
    }

    /// `splitCsvRecords`: line breaks inside quotes stay in the record.
    private static func records(_ text: String) -> [String] {
        var records: [String] = []
        var record = ""
        var insideQuotes = false
        for character in text {
            if character == "\"" {
                insideQuotes.toggle()
            }
            if character == "\n", !insideQuotes {
                records.append(record)
                record = ""
            } else {
                record.append(character)
            }
        }
        if !record.isEmpty {
            records.append(record)
        }
        return records
    }

    /// `splitCSVLine`: commas inside quotes do not separate; quotes are dropped and columns trimmed.
    private static func columns(_ record: String) -> [String] {
        var columns: [String] = []
        var column = ""
        var insideQuotes = false
        for character in record {
            if character == "\"" {
                insideQuotes.toggle()
            } else if character == ",", !insideQuotes {
                columns.append(column.trimmingCharacters(in: .whitespaces))
                column = ""
            } else {
                column.append(character)
            }
        }
        columns.append(column.trimmingCharacters(in: .whitespaces))
        return columns
    }
}

extension ChannelMemory {
    /// What makes an imported repeater the same as a stored memory.
    fileprivate var importKey: String { "\(name)|\(HamFrequency.format(frequency))" }
}
