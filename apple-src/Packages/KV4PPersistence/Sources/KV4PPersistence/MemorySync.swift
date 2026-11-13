import Foundation

/// A sync of the memories with iCloud that has finished: which way they went, and when.
public struct MemorySync: Sendable, Equatable {
    public enum Direction: String, Sendable {
        /// Changes from iCloud, made on another device, came to this one.
        case download
        /// Changes made on this device went to iCloud.
        case upload
    }

    public let direction: Direction
    public let started: Date
    public let finished: Date

    public init(direction: Direction, started: Date, finished: Date) {
        self.direction = direction
        self.started = started
        self.finished = finished
    }

    /// For the log: the direction and how long it took, such as "download, 0.4 s".
    public var summary: String {
        let seconds = max(0, finished.timeIntervalSince(started))
        return "\(direction.rawValue), \(String(format: "%.1f", seconds)) s"
    }
}
