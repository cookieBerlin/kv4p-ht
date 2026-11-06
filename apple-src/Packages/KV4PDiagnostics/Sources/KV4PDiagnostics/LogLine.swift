import Foundation

/// One line of the log, as the live view shows it (ADR-0059).
public struct LogLine: Equatable, Identifiable, Sendable {
    /// Given by whoever keeps the list, as lines from the file and from the app come together there.
    public var id = 0
    public let date: Date
    public let level: DiagnosticLog.Level
    public let category: DiagnosticLog.Category
    public let message: String

    public init(date: Date, level: DiagnosticLog.Level, category: DiagnosticLog.Category, message: String) {
        self.date = date
        self.level = level
        self.category = category
        self.message = message
    }

    /// As the file holds it.
    public var text: String {
        "\(date.ISO8601Format()) \(level.rawValue) \(category.rawValue): \(message)"
    }

    /// `nil` for what is not a line of the log, as the first one after a file was read only in part.
    public init?(parsing text: String) {
        let parts = text.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3,
            let date = try? Date(String(parts[0]), strategy: .iso8601),
            let level = DiagnosticLog.Level(rawValue: String(parts[1])),
            let colon = parts[2].firstIndex(of: ":"),
            let category = DiagnosticLog.Category(rawValue: String(parts[2][..<colon]))
        else { return nil }
        self.init(
            date: date,
            level: level,
            category: category,
            message: String(parts[2][colon...].dropFirst().drop { $0 == " " })
        )
    }
}

/// What the live view looks for; remembered on this device.
public struct LogFilter: Codable, Equatable, Sendable {
    /// None means all.
    public var levels: Set<DiagnosticLog.Level>
    /// None means all.
    public var categories: Set<DiagnosticLog.Category>
    public var search: String

    public init(
        levels: Set<DiagnosticLog.Level> = [],
        categories: Set<DiagnosticLog.Category> = [],
        search: String = ""
    ) {
        self.levels = levels
        self.categories = categories
        self.search = search
    }

    public var isEmpty: Bool {
        levels.isEmpty && categories.isEmpty && search.isEmpty
    }

    public func matches(_ line: LogLine) -> Bool {
        (levels.isEmpty || levels.contains(line.level))
            && (categories.isEmpty || categories.contains(line.category))
            && (search.isEmpty || line.message.localizedCaseInsensitiveContains(search))
    }
}

/// How much is stored.
public struct LogSummary: Equatable, Sendable {
    public let byteCount: Int
    /// The day of the oldest line, as `yyyy-MM-dd`.
    public let since: String?

    public init(byteCount: Int, since: String?) {
        self.byteCount = byteCount
        self.since = since
    }
}
