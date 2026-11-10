import Foundation
import KV4PPersistence
import KV4PProtocol

/// A list of repeaters the user can import from a file (ADR-0065).
public enum RepeaterList: Sendable {
    /// RepeaterBook's CSV export (`RepeaterBookImport`).
    case repeaterBook
    /// The CSV export of the DARC repeater lists (`DARCImport`).
    case darc

    /// The notice for a file that is not of this list.
    public var notThisList: String {
        switch self {
        case .repeaterBook: "This file is not a RepeaterBook CSV export."
        case .darc: "This file is not a DARC repeater list."
        }
    }
}

/// The access tone an import gives its new repeaters.
public struct ImportAccessTone: Equatable, Sendable {
    public var hz: Int
    public var lengthMs: Int

    /// What German repeaters mostly take.
    public static let standard = ImportAccessTone(hz: 1750, lengthMs: 3000)

    public init(hz: Int, lengthMs: Int) {
        self.hz = hz
        self.lengthMs = lengthMs
    }
}

/// What importing a list of repeaters would do.
public struct RepeaterImportPreview: Equatable, Sendable {
    /// The new memories.
    public let memories: [ChannelMemory]
    /// Memories the group has, with what they lacked from the list.
    public let completed: [ChannelMemory]
    /// Entries outside 2 m and 70 cm, which no module receives.
    public let outOfRange: Int
    /// Entries the group already has, or that the file lists twice.
    public let duplicates: Int
    /// Entries of another mode than FM.
    public let otherModes: Int

    public init(
        memories: [ChannelMemory],
        completed: [ChannelMemory] = [],
        outOfRange: Int,
        duplicates: Int,
        otherModes: Int
    ) {
        self.memories = memories
        self.completed = completed
        self.outOfRange = outOfRange
        self.duplicates = duplicates
        self.otherModes = otherModes
    }

    /// What is imported: "2 repeaters", "1 repeater and 3 beacons", "2 beacons".
    public var imported: String {
        let beacons = memories.count { $0.kind == .beacon }
        let repeaters = Self.counted(memories.count - beacons, "repeater")
        guard beacons > 0 else { return repeaters }
        let counted = Self.counted(beacons, "beacon")
        return beacons == memories.count ? counted : repeaters + " and " + counted
    }

    public var summary: String {
        var leftOut: [String] = []
        if otherModes > 0 { leftOut.append("\(otherModes) of another mode") }
        if outOfRange > 0 {
            leftOut.append("\(outOfRange) outside " + RFModuleType.allCases.map(\.band).joined(separator: " and "))
        }
        if duplicates > 0 { leftOut.append("\(duplicates) already in this group") }
        let count = imported + " to import" + (completed.isEmpty ? "" : ", \(completed.count) to complete") + "."
        return leftOut.isEmpty ? count : count + " Left out: " + leftOut.joined(separator: ", ") + "."
    }

    private static func counted(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }
}

/// What the imports of repeater lists share.
public enum RepeaterImport {
    /// The text of a file in UTF-8 or, failing that, Windows-1252, as the DARC lists may come in either. Foundation
    /// drops a byte order mark.
    public static func text(from data: Data) -> String {
        String(data: data, encoding: .utf8) ?? String(decoding: data.flatMap(windows1252), as: UTF8.self)
    }

    /// Windows-1252 as UTF-8 bytes; Foundation's decoder refuses its five unassigned bytes.
    private static func windows1252(_ byte: UInt8) -> [UInt8] {
        let scalar = String(data: Data([byte]), encoding: .windowsCP1252)?.unicodeScalars.first ?? "\u{FFFD}"
        return Array(String(scalar).utf8)
    }

    /// The new memories of `group` among `entries` within 2 m and 70 cm, and those it has that the entries complete: a
    /// memory counts as present if `group` has one with the same name and frequency. New repeaters get `accessTone`.
    static func preview(
        _ entries: [ChannelMemory],
        otherModes: Int,
        group: String,
        existing: [ChannelMemory],
        accessTone: ImportAccessTone? = nil
    ) -> RepeaterImportPreview {
        let inBand = entries.filter { RFModuleType.receiving($0.frequency) != nil }
        var present = Dictionary(
            existing.filter { $0.group == group }.map { ($0.importKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var new: [ChannelMemory] = []
        var completed: [ChannelMemory] = []
        for entry in inBand {
            if let memory = present[entry.importKey] {
                let filled = memory.completed(from: entry)
                if filled != memory {
                    completed.append(filled)
                    present[entry.importKey] = filled
                }
            } else {
                var entry = entry
                if entry.kind == .repeater, let accessTone {
                    entry.accessToneHz = accessTone.hz
                    entry.accessToneLengthMs = accessTone.lengthMs
                }
                new.append(entry)
                present[entry.importKey] = entry
            }
        }
        return RepeaterImportPreview(
            memories: new,
            completed: completed,
            outOfRange: entries.count - inBand.count,
            duplicates: inBand.count - new.count - completed.count,
            otherModes: otherModes
        )
    }

    /// The records of a CSV file; line breaks inside quotes stay in the record (Android `splitCsvRecords`).
    static func records(_ text: String) -> [String] {
        // "\r\n" is one Character in Swift; Android reads lines without "\r".
        let text = text.replacing("\r\n", with: "\n").replacing("\r", with: "")
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
        return records.filter { !$0.allSatisfy(\.isWhitespace) }
    }

    /// The columns of a record: a separator inside quotes does not separate; quotes are dropped and columns trimmed
    /// (Android `splitCSVLine`).
    static func columns(_ record: String, separator: Character) -> [String] {
        var columns: [String] = []
        var column = ""
        var insideQuotes = false
        for character in record {
            if character == "\"" {
                insideQuotes.toggle()
            } else if character == separator, !insideQuotes {
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
    /// What makes an imported entry the same as a stored memory.
    fileprivate var importKey: String { "\(name)|\(HamFrequency.format(frequency))" }

    /// The memory with what it lacks from `entry`: a comment, and a position if it has none or half of one. What the
    /// user set stays.
    fileprivate func completed(from entry: ChannelMemory) -> ChannelMemory {
        var memory = self
        if memory.comment.isEmpty {
            memory.comment = entry.comment
        }
        if memory.latitude == nil || memory.longitude == nil, entry.latitude != nil {
            memory.latitude = entry.latitude
            memory.longitude = entry.longitude
        }
        return memory
    }
}
