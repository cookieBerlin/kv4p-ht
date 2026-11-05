import Foundation
import Synchronization
import Testing

@testable import KV4PDiagnostics

private final class TestTime: Sendable {
    private let value = Mutex<Int64>(1_000_000)

    var ms: Int64 { value.withLock { $0 } }

    func advance(by ms: Int64) {
        value.withLock { $0 += ms }
    }
}

/// The log on the device, in files limited in age and size (ADR-0059).
@Suite("Diagnostic log")
struct DiagnosticLogTests {
    private static let day: Int64 = 86_400_000

    private static func folder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    }

    private static func names(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    @Test("a line has its time, level and category")
    func format() {
        let store = MemoryLogStore()
        let log = DiagnosticLog(store: store, now: { 1_000 })
        log.log(.error, .connection, "It failed")
        log.log(.info, .audio, "It works")
        #expect(
            store.read() == """
                1970-01-01T00:00:01Z ERROR connection: It failed
                1970-01-01T00:00:01Z INFO audio: It works

                """
        )
    }

    @Test("details are logged only until the given time")
    func details() {
        let store = MemoryLogStore()
        let time = TestTime()
        let log = DiagnosticLog(store: store, now: { time.ms })
        log.log(.detail, .aprs, "Not yet")
        log.detailedUntilMs = time.ms + 100
        log.log(.detail, .aprs, "Now")
        time.advance(by: 100)
        log.log(.detail, .aprs, "Too late")
        log.log(.info, .aprs, "Always")
        #expect(store.read().contains("DETAIL aprs: Now"))
        #expect(!store.read().contains("Not yet"))
        #expect(!store.read().contains("Too late"))
        #expect(store.read().contains("Always"))
        log.deleteAll()
        #expect(store.read().isEmpty)
    }

    @Test("an error is told by its domain and code, as its text can hold a path with the user's name")
    func errors() {
        let error = NSError(domain: "Domain", code: 7, userInfo: [NSLocalizedDescriptionKey: "/Users/name/file"])
        #expect(DiagnosticLog.describe(error) == "Domain 7")
    }

    @Test("a path never reaches a line, as it can hold a serial number or the user's name")
    func redacts() {
        let store = MemoryLogStore()
        let log = DiagnosticLog(store: store, now: { 0 })
        log.log(.error, .connection, #"Failed: portUnavailable(path: "/dev/cu.usbserial-0001", errno: 2)"#)
        log.log(.error, .storage, "/Users/name/file cannot be opened")
        #expect(store.read().contains(#"portUnavailable(path: "[path]", errno: 2)"#))
        #expect(store.read().contains("[path] cannot be opened"))
        #expect(!store.read().contains("usbserial"))
        #expect(!store.read().contains("name"))
    }

    @Test("the file keeps lines across restarts, oldest first")
    func file() throws {
        let folder = Self.folder()
        let first = LogFile(folder: folder)
        first.append("one", atMs: 0)
        #expect(first.read() == "one\n")
        let second = LogFile(folder: folder)
        second.append("two", atMs: 1)
        second.append("three", atMs: Self.day)
        #expect(second.read() == "one\ntwo\nthree\n")
        #expect(try Self.names(in: folder) == ["kv4p-1970-01-01-00.log", "kv4p-1970-01-02-00.log"])
    }

    @Test("the file is left out of backups")
    func backups() throws {
        let folder = Self.folder()
        let file = LogFile(folder: folder)
        file.append("one", atMs: 0)
        _ = file.read()
        let url = folder.appending(path: "kv4p-1970-01-01-00.log")
        #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test("a full file goes on in the next one")
    func parts() throws {
        let folder = Self.folder()
        let file = LogFile(folder: folder, partLimit: 5)
        file.append("12345", atMs: 0)
        file.append("next", atMs: 1)
        #expect(file.read() == "12345\nnext\n")
        #expect(try Self.names(in: folder) == ["kv4p-1970-01-01-00.log", "kv4p-1970-01-01-01.log"])
    }

    @Test("files go after 7 days")
    func age() throws {
        let folder = Self.folder()
        let file = LogFile(folder: folder)
        file.append("old", atMs: 0)
        file.append("kept", atMs: 7 * Self.day)
        #expect(file.read() == "old\nkept\n")
        file.append("new", atMs: 8 * Self.day)
        #expect(file.read() == "kept\nnew\n")
    }

    @Test("no more than 8 files stay, the newest")
    func count() throws {
        let folder = Self.folder()
        let file = LogFile(folder: folder, partLimit: 1)
        for number in 0..<10 {
            file.append("\(number)", atMs: 0)
        }
        #expect(file.read() == (2..<10).map { "\($0)\n" }.joined())
    }

    @Test("reading gives the newest part of what is there")
    func readLimit() {
        let file = LogFile(folder: Self.folder(), partLimit: 100, readLimit: 8)
        file.append("older", atMs: 0)
        file.append("newer", atMs: 0)
        #expect(file.read() == "r\nnewer\n")
    }

    @Test("everything can be deleted, and the log goes on")
    func deleteAll() {
        let file = LogFile(folder: Self.folder())
        file.append("one", atMs: 0)
        file.deleteAll()
        #expect(file.read().isEmpty)
        file.append("two", atMs: 0)
        #expect(file.read() == "two\n")
    }

    @Test("the file says how much it holds and since when")
    func fileSummary() {
        let file = LogFile(folder: Self.folder(), partLimit: 5)
        #expect(file.summary() == LogSummary(byteCount: 0, since: nil))
        file.append("12345", atMs: 0)
        file.append("next", atMs: Self.day)
        #expect(file.summary() == LogSummary(byteCount: 11, since: "1970-01-01"))
    }

    @Test("memory says the same")
    func memorySummary() {
        let store = MemoryLogStore()
        let log = DiagnosticLog(store: store, now: { 0 })
        #expect(log.summary() == LogSummary(byteCount: 0, since: nil))
        log.log(.info, .app, "One")
        #expect(log.summary().since == "1970-01-01")
        #expect(log.summary().byteCount == store.read().utf8.count)
    }

    @Test("a live reader gets the lines from now on, filtered like the file, and a new one replaces it")
    func live() async {
        let log = DiagnosticLog(store: MemoryLogStore(), now: { 0 })
        log.log(.info, .app, "Before")
        var first = log.liveLines().makeAsyncIterator()
        log.log(.error, .connection, "Path /dev/cu.usbserial-0001 failed")
        let line = await first.next()
        #expect(line?.level == .error)
        #expect(line?.category == .connection)
        #expect(line?.message == "Path [path] failed")
        var second = log.liveLines().makeAsyncIterator()
        #expect(await first.next() == nil)
        log.log(.info, .app, "After")
        #expect(await second.next()?.message == "After")
    }
}

/// Lines as the live view reads and filters them (ADR-0059).
@Suite("Log lines")
struct LogLineTests {
    private static let line = LogLine(
        date: Date(timeIntervalSince1970: 1),
        level: .error,
        category: .connection,
        message: "It failed: for now"
    )

    @Test("a line comes back from its text")
    func parses() {
        #expect(Self.line.text == "1970-01-01T00:00:01Z ERROR connection: It failed: for now")
        #expect(LogLine(parsing: Self.line.text) == Self.line)
    }

    @Test("what is not a line is left out")
    func notLines() {
        #expect(LogLine(parsing: "") == nil)
        #expect(LogLine(parsing: "r") == nil)
        #expect(LogLine(parsing: "no ERROR connection: It") == nil)
        #expect(LogLine(parsing: "1970-01-01T00:00:01Z WRONG connection: It") == nil)
        #expect(LogLine(parsing: "1970-01-01T00:00:01Z ERROR wrong: It") == nil)
        #expect(LogLine(parsing: "1970-01-01T00:00:01Z ERROR connection It") == nil)
    }

    @Test("a filter looks at the level, the category and the text; empty finds everything")
    func filter() {
        #expect(LogFilter().isEmpty)
        #expect(LogFilter().matches(Self.line))
        #expect(LogFilter(levels: [.error]).matches(Self.line))
        #expect(!LogFilter(levels: [.info]).matches(Self.line))
        #expect(LogFilter(categories: [.connection]).matches(Self.line))
        #expect(!LogFilter(categories: [.audio]).matches(Self.line))
        #expect(LogFilter(search: "FAILED").matches(Self.line))
        #expect(!LogFilter(search: "other").matches(Self.line))
        #expect(!LogFilter(search: "x").isEmpty)
        #expect(!LogFilter(levels: [.info]).isEmpty)
        #expect(!LogFilter(categories: [.app]).isEmpty)
    }
}
