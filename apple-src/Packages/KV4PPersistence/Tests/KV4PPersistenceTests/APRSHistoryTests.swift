import Foundation
import Testing

@testable import KV4PPersistence

/// The stored APRS packets: local to the device (ADR-0057).
@Suite("APRS history")
struct APRSHistoryTests {
    private static func entry(_ id: Int64, at lastSeenMs: Int64 = 0, payload: String = "a") -> APRSHistoryEntry {
        APRSHistoryEntry(
            id: id,
            lastSeenMs: lastSeenMs,
            kind: 3,
            fromCallsign: "N1CALL",
            toCallsign: "N0CALL",
            isInternetOnly: id.isMultiple(of: 2),
            payload: Data(payload.utf8)
        )
    }

    @Test("an entry comes back as it was saved")
    func roundTrip() async throws {
        let history = try SwiftDataAPRSHistory.inMemory()
        try await history.save([Self.entry(1, at: 10, payload: "one"), Self.entry(2, at: 20)])
        #expect(
            try await history.page(before: nil, limit: 10) == [
                Self.entry(2, at: 20), Self.entry(1, at: 10, payload: "one"),
            ]
        )
        #expect(try await history.count() == 2)
    }

    @Test("saving an id again replaces it")
    func replaces() async throws {
        let history = try SwiftDataAPRSHistory.inMemory()
        try await history.save([Self.entry(1, at: 10)])
        try await history.save([Self.entry(1, at: 30, payload: "new")])
        #expect(try await history.page(before: nil, limit: 10) == [Self.entry(1, at: 30, payload: "new")])
        #expect(try await history.count() == 1)
    }

    @Test("pages go back in time, and include the moment they start from")
    func pages() async throws {
        let history = try SwiftDataAPRSHistory.inMemory()
        try await history.save((1...5).map { Self.entry($0, at: $0 * 10) })
        #expect(try await history.page(before: nil, limit: 2).map(\.id) == [5, 4])
        #expect(try await history.page(before: 40, limit: 2).map(\.id) == [4, 3])
    }

    @Test("a filter finds by callsign and type, in any case, over all that is stored")
    func filters() async throws {
        let history = try SwiftDataAPRSHistory.inMemory()
        let entries = [
            APRSHistoryEntry(
                id: 1,
                lastSeenMs: 1,
                kind: 1,
                fromCallsign: "N1CALL",
                toCallsign: "N0CALL",
                isInternetOnly: false,
                payload: Data()
            ),
            APRSHistoryEntry(
                id: 2,
                lastSeenMs: 2,
                kind: 3,
                fromCallsign: "N2CALL",
                toCallsign: nil,
                isInternetOnly: false,
                payload: Data()
            ),
            APRSHistoryEntry(
                id: 3,
                lastSeenMs: 3,
                kind: 4,
                fromCallsign: "N1CALL-9",
                toCallsign: nil,
                isInternetOnly: false,
                payload: Data()
            ),
        ]
        try await history.save(entries)
        func ids(_ filter: APRSHistoryFilter, before: Int64? = nil, limit: Int = 10) async throws -> [Int64] {
            try await history.page(before: before, limit: limit, filter: filter).map(\.id)
        }
        #expect(try await ids(APRSHistoryFilter()) == [3, 2, 1])
        #expect(try await ids(APRSHistoryFilter(callsign: "n1call")) == [3, 1])
        #expect(try await ids(APRSHistoryFilter(callsign: " N0 ")) == [1])
        #expect(try await ids(APRSHistoryFilter(kinds: [3, 4])) == [3, 2])
        #expect(try await ids(APRSHistoryFilter(callsign: "N1", kinds: [4])) == [3])
        #expect(try await ids(APRSHistoryFilter(callsign: "N1"), before: 2, limit: 1) == [1])
        #expect(try await ids(APRSHistoryFilter(callsign: "N1", participant: "N0")) == [1])
        #expect(!APRSHistoryFilter(participant: "x").isEmpty)
        #expect(APRSHistoryFilter().isEmpty)
        #expect(!APRSHistoryFilter(callsign: "x").isEmpty)
        #expect(!APRSHistoryFilter(kinds: [1]).isEmpty)
    }

    @Test("an entry, the old ones or all can go")
    func deletes() async throws {
        let history = try SwiftDataAPRSHistory.inMemory()
        try await history.save((1...5).map { Self.entry($0, at: $0 * 10) })
        try await history.delete(id: 3)
        try await history.delete(id: 99)
        #expect(try await history.page(before: nil, limit: 10).map(\.id) == [5, 4, 2, 1])
        try await history.deleteOlder(than: 20, except: APRSHistoryFilter(kinds: [99]))
        #expect(try await history.page(before: nil, limit: 10).map(\.id) == [5, 4, 2])
        try await history.deleteAll()
        #expect(try await history.count() == 0)
    }

    @Test("the highest id is known, as new ones must not repeat it")
    func highestId() async throws {
        let history = try SwiftDataAPRSHistory.inMemory()
        #expect(try await history.highestId() == 0)
        try await history.save([Self.entry(7, at: 1), Self.entry(3, at: 50)])
        #expect(try await history.highestId() == 7)
    }

    @Test("the entries survive a restart, in a store of their own")
    func survives() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).store")
        try await SwiftDataAPRSHistory(storeURL: url).save([Self.entry(1, at: 10)])
        #expect(try await SwiftDataAPRSHistory(storeURL: url).count() == 1)
    }

    @Test("the store of an earlier format goes, and the new one stays across restarts")
    func dropsFormerStore() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let former = ["APRSHistory.store", "APRSHistory.store-wal", "APRSHistory.store-shm"]
            .map { folder.appending(path: $0) }
        for file in former {
            try Data("old".utf8).write(to: file)
        }
        try await SwiftDataAPRSHistory.inFolder(folder).save([Self.entry(1, at: 10)])
        for file in former {
            #expect(!FileManager.default.fileExists(atPath: file.path))
        }
        #expect(try await SwiftDataAPRSHistory.inFolder(folder).count() == 1)
    }

    @Test("old entries go, except those that fit a filter, which can go by a time of their own")
    func keepsMessages() async throws {
        let history = try SwiftDataAPRSHistory.inMemory()
        let message = APRSHistoryEntry(
            id: 1,
            lastSeenMs: 10,
            kind: 1,
            fromCallsign: "N1CALL",
            toCallsign: "N0CALL",
            isInternetOnly: false,
            payload: Data()
        )
        let other = APRSHistoryEntry(
            id: 2,
            lastSeenMs: 10,
            kind: 1,
            fromCallsign: "N1CALL",
            toCallsign: "N2CALL",
            isInternetOnly: false,
            payload: Data()
        )
        let newer = APRSHistoryEntry(
            id: 3,
            lastSeenMs: 50,
            kind: 1,
            fromCallsign: "N0CALL",
            toCallsign: "N1CALL",
            isInternetOnly: false,
            payload: Data()
        )
        try await history.save([message, other, newer, Self.entry(4, at: 10)])
        let chats = APRSHistoryFilter(kinds: [1], participant: "N0CALL")
        try await history.deleteOlder(than: 20, except: chats)
        #expect(try await history.page(before: nil, limit: 10).map(\.id) == [3, 1])
        try await history.deleteOlder(than: 20, matching: chats)
        #expect(try await history.page(before: nil, limit: 10).map(\.id) == [3])
        try await history.deleteOlder(than: 60, matching: APRSHistoryFilter())
        #expect(try await history.count() == 0)
    }
}
