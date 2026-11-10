import Foundation

/// The repeater offset of a memory; raw values as in the Android `ChannelMemory`.
public enum MemoryOffset: Int, CaseIterable, Codable, Sendable {
    case none = 0
    case down = 1
    case up = 2
}

/// What a memory is (ADR-0065): a repeater, a beacon that only transmits, or any other frequency.
public enum MemoryKind: String, CaseIterable, Codable, Sendable {
    case frequency
    case repeater
    case beacon
}

/// A stored channel (Android `ChannelMemory`). `frequency` is the RX frequency in MHz; tones are `CTCSS` labels.
public struct ChannelMemory: Hashable, Identifiable, Sendable {
    /// Assigned by the repository, for this device; it is also the memory id sent to the radio.
    public var id: Int32
    public var name: String
    public var frequency: Float
    public var offset: MemoryOffset
    public var offsetKHz: Int
    public var txTone: String
    public var rxTone: String
    /// Empty for no group.
    public var group: String
    public var skipDuringScan: Bool
    /// The tone that opens the repeater, in Hz: 0 for none, `nil` to follow the settings.
    public var accessToneHz: Int?
    /// How long that tone lasts, in ms; `nil` to follow the settings.
    public var accessToneLengthMs: Int?
    public var kind: MemoryKind
    /// Empty for none.
    public var comment: String
    /// The position in decimal degrees, north and east positive; `nil` if unknown.
    public var latitude: Double?
    public var longitude: Double?

    public init(
        id: Int32 = 0,
        name: String,
        frequency: Float,
        offset: MemoryOffset = .none,
        offsetKHz: Int = 600,
        txTone: String = "None",
        rxTone: String = "None",
        group: String = "",
        skipDuringScan: Bool = false,
        accessToneHz: Int? = nil,
        accessToneLengthMs: Int? = nil,
        kind: MemoryKind = .frequency,
        comment: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.frequency = frequency
        self.offset = offset
        self.offsetKHz = offsetKHz
        self.txTone = txTone
        self.rxTone = rxTone
        self.group = group
        self.skipDuringScan = skipDuringScan
        self.accessToneHz = accessToneHz
        self.accessToneLengthMs = accessToneLengthMs
        self.kind = kind
        self.comment = comment
        self.latitude = latitude
        self.longitude = longitude
    }

    /// The distinct, non-empty group names, in the order of their memories.
    public static func groups(in memories: [ChannelMemory]) -> [String] {
        blocks(in: memories).map(\.name).filter { !$0.isEmpty }
    }

    /// The memories group by group; a group stands where its first memory is (ADR-0042).
    public static func blocks(in memories: [ChannelMemory]) -> [MemoryGroup] {
        var blocks: [MemoryGroup] = []
        for memory in memories {
            if let index = blocks.firstIndex(where: { $0.name == memory.group }) {
                blocks[index].memories.append(memory)
            } else {
                blocks.append(MemoryGroup(name: memory.group, memories: [memory]))
            }
        }
        return blocks
    }

    /// The memories with those of a group next to each other.
    public static func arranged(_ memories: [ChannelMemory]) -> [ChannelMemory] {
        blocks(in: memories).flatMap(\.memories)
    }

    /// The ids of all memories after moving whole groups, with `destination` as in SwiftUI's `onMove`.
    public static func order(ofBlocks blocks: [MemoryGroup], movingGroups offsets: IndexSet, to destination: Int)
        -> [Int32]
    {
        blocks.moved(offsets, to: destination).flatMap(\.memories).map(\.id)
    }

    /// The ids of all memories after moving some inside the group `name`.
    public static func order(
        ofBlocks blocks: [MemoryGroup],
        inGroup name: String,
        moving offsets: IndexSet,
        to destination: Int
    ) -> [Int32] {
        blocks.flatMap { $0.name == name ? $0.memories.moved(offsets, to: destination) : $0.memories }.map(\.id)
    }
}

/// A group and its memories; an empty name means the memories without a group.
public struct MemoryGroup: Equatable, Identifiable, Sendable {
    public let name: String
    public var memories: [ChannelMemory]

    public var id: String { name }
}

extension Array {
    /// The elements at `offsets` moved before the element at `destination`, as SwiftUI's `onMove` reports it.
    fileprivate func moved(_ offsets: IndexSet, to destination: Int) -> [Element] {
        let rest = indices.filter { !offsets.contains($0) }.map { self[$0] }
        let insertion = destination - offsets.count { $0 < destination }
        return Array(rest[..<insertion] + offsets.map { self[$0] } + rest[insertion...])
    }
}

/// Stores the channel memories (ADR-0007).
public protocol MemoryRepository: Sendable {
    /// All memories in their stored order, those of a group next to each other.
    func all() async throws -> [ChannelMemory]
    /// Stores new memories and returns them with their assigned ids.
    func insert(_ memories: [ChannelMemory]) async throws -> [ChannelMemory]
    /// Replaces the memory with the same id; unknown ids are ignored. A new group puts it at the end of that group.
    func update(_ memory: ChannelMemory) async throws
    func delete(id: Int32) async throws
    /// Puts the memories into the order of `ids`; those not named follow in their order.
    func reorder(_ ids: [Int32]) async throws
    /// Gives the memories of `group` the name `newName`; they keep their place.
    func renameGroup(_ group: String, to newName: String) async throws
    /// Reports that the memories have changed from outside, through iCloud.
    var changes: AsyncStream<Void> { get }
    /// Reports when a sync with iCloud has finished.
    var finishedSyncs: AsyncStream<Date> { get }
}

extension MemoryRepository {
    public var changes: AsyncStream<Void> { AsyncStream { $0.finish() } }
    public var finishedSyncs: AsyncStream<Date> { AsyncStream { $0.finish() } }
}
