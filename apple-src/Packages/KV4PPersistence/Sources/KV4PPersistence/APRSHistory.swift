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

/// What to look for in the APRS list; empty finds everything.
public struct APRSHistoryFilter: Equatable, Sendable {
    /// Found in the sender or the recipient, in any case.
    public var callsign: String
    /// The kinds of packet; none means all.
    public var kinds: Set<Int>
    /// A callsign that must be in the packet as well, whatever the search says.
    public var participant: String

    public init(callsign: String = "", kinds: Set<Int> = [], participant: String = "") {
        self.callsign = callsign
        self.kinds = kinds
        self.participant = participant
    }

    public var isEmpty: Bool { term.isEmpty && kinds.isEmpty && participant.isEmpty }

    /// The callsign as the store looks for it.
    public var term: String {
        callsign.trimmingCharacters(in: .whitespaces).uppercased()
    }
}

/// Keeps the APRS list across restarts, on this device only.
public protocol APRSHistoryStoring: Sendable {
    /// Adds the entries, or replaces those with the same id.
    func save(_ entries: [APRSHistoryEntry]) async throws
    /// The newest entries that fit, up to and including `lastSeenMs`, newest first.
    func page(before lastSeenMs: Int64?, limit: Int, filter: APRSHistoryFilter) async throws -> [APRSHistoryEntry]
    func delete(id: Int64) async throws
    func deleteOlder(than lastSeenMs: Int64) async throws
    func deleteAll() async throws
    func count() async throws -> Int
    /// 0 if there are none.
    func highestId() async throws -> Int64
}

extension APRSHistoryStoring {
    public func page(before lastSeenMs: Int64?, limit: Int) async throws -> [APRSHistoryEntry] {
        try await page(before: lastSeenMs, limit: limit, filter: APRSHistoryFilter())
    }
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
    /// Sender and recipient in upper case, to search both at once.
    var callsigns: String

    init(_ entry: APRSHistoryEntry) {
        callsigns = "\(entry.fromCallsign) \(entry.toCallsign ?? "")".uppercased()
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

    /// The file name changes with a format of the store that cannot follow from the one before: what was stored goes, as
    /// packets are not worth a migration (ADR-0057).
    private static let storeName = "APRSPackets.store"
    private static let formerStoreNames = ["APRSHistory.store"]

    /// The store of this app in `folder`, without those of earlier formats.
    public static func inFolder(_ folder: URL) throws -> SwiftDataAPRSHistory {
        for name in formerStoreNames {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: folder.appending(path: name + suffix))
            }
        }
        return try SwiftDataAPRSHistory(storeURL: folder.appending(path: storeName))
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

    public func page(before lastSeenMs: Int64?, limit: Int, filter: APRSHistoryFilter) throws -> [APRSHistoryEntry] {
        let latest = lastSeenMs ?? .max
        let term = filter.term
        let kinds = Array(filter.kinds)
        let hasNoKinds = kinds.isEmpty
        let participant = filter.participant
        var descriptor = FetchDescriptor<StoredAPRSPacket>(
            predicate: #Predicate { packet in
                packet.lastSeenMs <= latest && (term.isEmpty || packet.callsigns.contains(term))
                    && (hasNoKinds || kinds.contains(packet.kind))
                    && (participant.isEmpty || packet.callsigns.contains(participant))
            },
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
