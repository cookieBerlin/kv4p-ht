import Foundation

/// Crash data from the system, until it is reported or deleted (ADR-0059). A new one is offered once.
public final class CrashReportStore: Sendable {
    private static let kept = 5

    private let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    private var newFolder: URL { folder.appending(path: "new") }

    private func names(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    /// Whether this crash was not known yet. The name starts with a number, so names sort by age; `id` comes from the
    /// system and is the way to know a report again.
    @discardableResult
    public func add(id: String, json: String) -> Bool {
        let name = "\(String(format: "%010d", nextNumber() + 1))-\(id).json"
        let known = (names(in: folder) + names(in: newFolder)).contains { $0.hasSuffix("-\(id).json") }
        guard !known else { return false }
        try? FileManager.default.createDirectory(at: newFolder, withIntermediateDirectories: true)
        try? Data(json.utf8).write(to: newFolder.appending(path: name))
        trim()
        return true
    }

    private func nextNumber() -> Int {
        (names(in: folder) + names(in: newFolder)).compactMap { Int($0.prefix(10)) }.max() ?? 0
    }

    private func trim() {
        let all = (reports(in: folder) + reports(in: newFolder)).sorted { $0.lastPathComponent < $1.lastPathComponent }
        for old in all.dropLast(Self.kept) {
            try? FileManager.default.removeItem(at: old)
        }
    }

    private func reports(in folder: URL) -> [URL] {
        names(in: folder).filter { $0.hasSuffix(".json") }.map { folder.appending(path: $0) }
    }

    public var hasNew: Bool {
        !reports(in: newFolder).isEmpty
    }

    public func markSeen() {
        for report in reports(in: newFolder) {
            try? FileManager.default.moveItem(at: report, to: folder.appending(path: report.lastPathComponent))
        }
    }

    /// Oldest first.
    public func all() -> [String] {
        (reports(in: folder) + reports(in: newFolder))
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    public func deleteAll() {
        for report in reports(in: folder) + reports(in: newFolder) {
            try? FileManager.default.removeItem(at: report)
        }
    }
}
