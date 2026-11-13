import Foundation
import Testing

@testable import KV4PPersistence

/// A finished sync of the memories with iCloud, as the log tells it.
@Suite("Memory sync")
struct MemorySyncEventTests {
    private static func sync(_ direction: MemorySync.Direction, seconds: Double) -> MemorySync {
        MemorySync(
            direction: direction,
            started: Date(timeIntervalSince1970: 100),
            finished: Date(timeIntervalSince1970: 100 + seconds)
        )
    }

    @Test("it says which way the memories went, and how long it took, to a tenth of a second")
    func summary() {
        #expect(Self.sync(.download, seconds: 0.43).summary == "download, 0.4 s")
        #expect(Self.sync(.upload, seconds: 12).summary == "upload, 12.0 s")
    }

    @Test("a sync whose end lies before its start counts as taking no time")
    func clockGoesBack() {
        #expect(Self.sync(.upload, seconds: -3).summary == "upload, 0.0 s")
    }
}
