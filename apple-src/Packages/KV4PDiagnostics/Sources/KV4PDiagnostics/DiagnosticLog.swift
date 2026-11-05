import Foundation
import os

/// Where the lines of the log stay.
public protocol LogStoring: Sendable {
    func append(_ line: String, atMs: Int64)
    func read() -> String
    func deleteAll()
}

/// What the app did, for a report on a problem (ADR-0059). A line never holds message texts, positions, callsigns,
/// passwords or the names of memories and radios, and the real-time audio paths do not log. Frequencies and times are
/// not private, as amateur radio is on air for everyone.
public final class DiagnosticLog: Sendable {
    public enum Level: String, Sendable {
        case error = "ERROR"
        case info = "INFO"
        case detail = "DETAIL"
    }

    public enum Category: String, Sendable {
        case app, connection, transmit, audio, permissions, sync, firmware, aprs, storage, location
    }

    private let store: any LogStoring
    private let now: @Sendable () -> Int64
    private let detailedUntil = OSAllocatedUnfairLock<Int64>(initialState: 0)

    public init(store: any LogStoring, now: @escaping @Sendable () -> Int64) {
        self.store = store
        self.now = now
    }

    /// `detail` lines are logged only before this time.
    public var detailedUntilMs: Int64 {
        get { detailedUntil.withLock { $0 } }
        set { detailedUntil.withLock { $0 = newValue } }
    }

    public func log(_ level: Level, _ category: Category, _ text: String) {
        let time = now()
        guard level != .detail || time < detailedUntilMs else { return }
        let date = Date(timeIntervalSince1970: Double(time) / 1000).ISO8601Format()
        let line = Self.redacted(text)
        store.append("\(date) \(level.rawValue) \(category.rawValue): \(line)", atMs: time)
        Logger(subsystem: "io.github.cookieberlin.kv4pht", category: category.rawValue)
            .log(level: level == .error ? .error : .info, "\(line, privacy: .public)")
    }

    public func read() -> String {
        store.read()
    }

    public func deleteAll() {
        store.deleteAll()
    }

    /// A serial port's name can hold a serial number, and a path the user's name; every line passes here.
    static func redacted(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"/(dev|Users|var|private|tmp)/[^\s,)"']*"#,
            with: "[path]",
            options: .regularExpression
        )
    }

    /// The text of an error can hold a path with the user's name, so it is told by its domain and code.
    public static func describe(_ error: any Error) -> String {
        let error = error as NSError
        return "\(error.domain) \(error.code)"
    }
}

/// Keeps the lines only while it exists.
public final class MemoryLogStore: LogStoring, Sendable {
    private let lines = OSAllocatedUnfairLock(initialState: "")

    public init() {}

    public func append(_ line: String, atMs: Int64) {
        lines.withLock { $0 += line + "\n" }
    }

    public func read() -> String {
        lines.withLock { $0 }
    }

    public func deleteAll() {
        lines.withLock { $0 = "" }
    }
}

/// The log in files named by their day, on this device and out of backups. Their age comes from the name, so that the app
/// reads no file dates, which Apple asks a reason for.
public final class LogFile: LogStoring, @unchecked Sendable {
    private static let keptDays: Int64 = 7
    private static let keptFiles = 8

    private let folder: URL
    private let partLimit: Int
    private let readLimit: Int
    /// Writes one after the other and away from the caller; `read` waits for them.
    private let queue = DispatchQueue(label: "io.github.cookieberlin.kv4pht.log")

    public init(folder: URL, partLimit: Int = 1_000_000, readLimit: Int = 2_000_000) {
        self.folder = folder
        self.partLimit = partLimit
        self.readLimit = readLimit
    }

    public func append(_ line: String, atMs: Int64) {
        queue.async { [self] in
            write(line, atMs: atMs)
        }
    }

    public func read() -> String {
        queue.sync {
            let parts = names().compactMap { try? Data(contentsOf: folder.appending(path: $0)) }
            return String(decoding: parts.reduce(Data(), +).suffix(readLimit), as: UTF8.self)
        }
    }

    public func deleteAll() {
        queue.sync {
            for name in names() {
                try? FileManager.default.removeItem(at: folder.appending(path: name))
            }
        }
    }

    private func names() -> [String] {
        let all = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return all.filter { $0.hasPrefix("kv4p-") && $0.hasSuffix(".log") }.sorted()
    }

    private static func day(atMs ms: Int64) -> String {
        String(Date(timeIntervalSince1970: Double(ms) / 1000).ISO8601Format().prefix(10))
    }

    private func write(_ line: String, atMs ms: Int64) {
        let day = Self.day(atMs: ms)
        let parts = names().filter { $0.hasPrefix("kv4p-\(day)-") }
        var part = 0
        var size = 0
        // By the name, as older parts may have gone.
        if let last = parts.last, let number = Int(last.dropLast(4).suffix(2)),
            let handle = try? FileHandle(forReadingFrom: folder.appending(path: last)),
            let end = try? handle.seekToEnd()
        {
            let isFull = end >= partLimit
            part = number + (isFull ? 1 : 0)
            size = isFull ? 0 : Int(end)
        }
        let url = folder.appending(path: "kv4p-\(day)-\(String(format: "%02d", part)).log")
        if size == 0 {
            create(url, atMs: ms)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data((line + "\n").utf8))
    }

    private func create(_ url: URL, atMs ms: Int64) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var excluded = url
        try? excluded.setResourceValues(values)
        let oldest = Self.day(atMs: ms - Self.keptDays * 86_400_000)
        let name = url.lastPathComponent
        let kept = names().filter { $0 == name || $0 >= "kv4p-\(oldest)-" }.suffix(Self.keptFiles)
        for old in Set(names()).subtracting(kept) {
            try? FileManager.default.removeItem(at: folder.appending(path: old))
        }
    }
}
