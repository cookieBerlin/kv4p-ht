/// The repeater offset of a memory; raw values as in the Android `ChannelMemory`.
public enum MemoryOffset: Int, CaseIterable, Codable, Sendable {
    case none = 0
    case down = 1
    case up = 2
}

/// A stored channel (Android `ChannelMemory`). `frequency` is the RX frequency in MHz; tones are `CTCSS` labels.
public struct ChannelMemory: Equatable, Identifiable, Sendable {
    /// Assigned by the repository; it is also the memory id sent to the radio.
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

    public init(
        id: Int32 = 0,
        name: String,
        frequency: Float,
        offset: MemoryOffset = .none,
        offsetKHz: Int = 600,
        txTone: String = "None",
        rxTone: String = "None",
        group: String = "",
        skipDuringScan: Bool = false
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
    }

    /// The distinct, non-empty group names, sorted.
    public static func groups(in memories: [ChannelMemory]) -> [String] {
        Set(memories.map(\.group)).filter { !$0.isEmpty }.sorted()
    }
}

/// Stores the channel memories (ADR-0007).
public protocol MemoryRepository: Sendable {
    /// All memories in the order they were added.
    func all() async throws -> [ChannelMemory]
    /// Stores new memories and returns them with their assigned ids.
    func insert(_ memories: [ChannelMemory]) async throws -> [ChannelMemory]
    /// Replaces the memory with the same id; unknown ids are ignored.
    func update(_ memory: ChannelMemory) async throws
    func delete(id: Int32) async throws
}
