import Foundation
import SwiftData

/// A stored APRS packet: the fields to look for it by, and the event as data of the APRS module (ADR-0057).
public struct APRSHistoryEntry: Equatable, Sendable {
    public let id: Int64
    public let lastSeenMs: Int64
    public let kind: Int
    public let fromCallsign: String
    public let toCallsign: String?
    public let isInternetOnly: Bool
    public let payload: Data

    public init(
        id: Int64,
        lastSeenMs: Int64,
        kind: Int,
        fromCallsign: String,
        toCallsign: String?,
        isInternetOnly: Bool,
        payload: Data
    ) {
        self.id = id
        self.lastSeenMs = lastSeenMs
        self.kind = kind
        self.fromCallsign = fromCallsign
        self.toCallsign = toCallsign
        self.isInternetOnly = isInternetOnly
        self.payload = payload
    }
}

/// Keeps the APRS list across restarts, on this device only.
public protocol APRSHistoryStoring: Sendable {
    /// Adds the entries, or replaces those with the same id.
    func save(_ entries: [APRSHistoryEntry]) async throws
    /// The newest entries up to and including `lastSeenMs`, newest first.
    func page(before lastSeenMs: Int64?, limit: Int) async throws -> [APRSHistoryEntry]
    func delete(id: Int64) async throws
    func deleteOlder(than lastSeenMs: Int64) async throws
    func deleteAll() async throws
    func count() async throws -> Int
    /// 0 if there are none.
    func highestId() async throws -> Int64
}

@Model
final class StoredAPRSPacket {
    #Index<StoredAPRSPacket>([\.lastSeenMs], [\.eventId])

    @Attribute(.unique) var eventId: Int64
    var lastSeenMs: Int64
    var kind: Int
    var fromCallsign: String
    var toCallsign: String?
    var isInternetOnly: Bool
    var payload: Data

    init(_ entry: APRSHistoryEntry) {
        eventId = entry.id
        lastSeenMs = entry.lastSeenMs
        kind = entry.kind
        fromCallsign = entry.fromCallsign
        toCallsign = entry.toCallsign
        isInternetOnly = entry.isInternetOnly
        payload = entry.payload
    }

    var entry: APRSHistoryEntry {
        APRSHistoryEntry(
            id: eventId,
            lastSeenMs: lastSeenMs,
            kind: kind,
            fromCallsign: fromCallsign,
            toCallsign: toCallsign,
            isInternetOnly: isInternetOnly,
            payload: payload
        )
    }
}

/// `APRSHistoryStoring` on SwiftData, in a store of its own that never syncs.
@ModelActor
public actor SwiftDataAPRSHistory: APRSHistoryStoring {
    public init(storeURL: URL) throws {
        try self.init(configuration: ModelConfiguration(url: storeURL, cloudKitDatabase: .none))
    }

    /// Keeps the entries only while the history exists (tests).
    public static func inMemory() throws -> SwiftDataAPRSHistory {
        try SwiftDataAPRSHistory(configuration: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private init(configuration: ModelConfiguration) throws {
        self.init(modelContainer: try ModelContainer(for: StoredAPRSPacket.self, configurations: configuration))
    }

    public func save(_ entries: [APRSHistoryEntry]) throws {
        for entry in entries {
            // The unique id makes this replace an entry that is there.
            modelContext.insert(StoredAPRSPacket(entry))
        }
        try modelContext.save()
    }

    public func page(before lastSeenMs: Int64?, limit: Int) throws -> [APRSHistoryEntry] {
        let latest = lastSeenMs ?? .max
        var descriptor = FetchDescriptor<StoredAPRSPacket>(
            predicate: #Predicate { $0.lastSeenMs <= latest },
            sortBy: [SortDescriptor(\.lastSeenMs, order: .reverse), SortDescriptor(\.eventId, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map(\.entry)
    }

    public func delete(id: Int64) throws {
        try modelContext.delete(model: StoredAPRSPacket.self, where: #Predicate { $0.eventId == id })
        try modelContext.save()
    }

    public func deleteOlder(than lastSeenMs: Int64) throws {
        try modelContext.delete(model: StoredAPRSPacket.self, where: #Predicate { $0.lastSeenMs < lastSeenMs })
        try modelContext.save()
    }

    public func deleteAll() throws {
        try modelContext.delete(model: StoredAPRSPacket.self)
        try modelContext.save()
    }

    public func count() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<StoredAPRSPacket>())
    }

    public func highestId() throws -> Int64 {
        var descriptor = FetchDescriptor<StoredAPRSPacket>(sortBy: [SortDescriptor(\.eventId, order: .reverse)])
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.eventId ?? 0
    }
}
