import Foundation
import KV4PPersistence
import KV4PProtocol

/// Turns a RepeaterBook CSV export into channel memories (Android `FindRepeatersActivity.parseRepeaterList` and
/// `findRepeatersSaveButtonClicked`).
public enum RepeaterBookImport {
    private static let usHeader = "Freq,Input,Offset,Tone,Location"
    private static let internationalHeader = "Output Freq,Input Freq,Offset,Uplink Tone"

    /// The new memories of `group` from an export, and those it completes; `nil` if the file is not one.
    public static func preview(fromCSV text: String, group: String, existing: [ChannelMemory]) -> RepeaterImportPreview?
    {
        guard let all = memories(fromCSV: text, group: group, range: -Float.infinity...Float.infinity) else {
            return nil
        }
        return RepeaterImport.preview(all, otherModes: 0, group: group, existing: existing)
    }

    /// The repeaters within `range` as memories of `group`; `nil` if the file is not a RepeaterBook export.
    public static func memories(fromCSV text: String, group: String, range: ClosedRange<Float>) -> [ChannelMemory]? {
        let records = RepeaterImport.records(text)
        guard let header = records.first else { return [] }
        let isUS = header.hasPrefix(usHeader)
        guard isUS || header.hasPrefix(internationalHeader) else { return nil }
        return records.dropFirst().compactMap { record in
            let columns = RepeaterImport.columns(record, separator: ",")
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
                group: group,
                kind: .repeater
            )
        }
    }
}
