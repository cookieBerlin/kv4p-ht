import Foundation
import Testing

@testable import KV4PRadio

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
}
