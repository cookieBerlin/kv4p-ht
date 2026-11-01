import Foundation
import KV4PPersistence
import KV4PProtocol

/// Turns a RepeaterBook CSV export into channel memories (Android `FindRepeatersActivity.parseRepeaterList` and
/// `findRepeatersSaveButtonClicked`).
public enum RepeaterBookImport {
    private static let usHeader = "Freq,Input,Offset,Tone,Location"
    private static let internationalHeader = "Output Freq,Input Freq,Offset,Uplink Tone"

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
