import Foundation
import KV4PTestSupport
import Testing

@testable import KV4PRadio

/// What the live view of the log shows (ADR-0059).
@MainActor
@Suite("Live log")
struct LiveLogTests {
    private static func setup(limit: Int = 2_000, initial: Int = 500) -> (DiagnosticLog, LiveLog) {
        let log = DiagnosticLog(store: MemoryLogStore(), now: { 0 })
        let live = LiveLog(diagnostics: log, limit: limit, initialLines: initial, showInterval: .milliseconds(1))
        return (log, live)
    }

    private static func messages(_ live: LiveLog) -> [String] {
        live.lines.map(\.message)
    }

    @Test("it starts with the end of the log, and goes on with new lines, each with an id of its own")
    func goesOn() async {
        let (log, live) = Self.setup(initial: 2)
        for number in 1...3 {
            log.log(.info, .app, "\(number)")
        }
        live.start()
        #expect(Self.messages(live) == ["2", "3"])
        log.log(.info, .app, "4")
        #expect(await eventually { Self.messages(live) == ["2", "3", "4"] })
        #expect(Set(live.lines.map(\.id)).count == 3)
        live.stop()
    }

    @Test("starting twice changes nothing, and after stopping it holds nothing and hears nothing")
    func stops() async {
        let (log, live) = Self.setup()
        log.log(.info, .app, "One")
        live.start()
        live.start()
        #expect(Self.messages(live) == ["One"])
        live.stop()
        #expect(live.lines.isEmpty)
        log.log(.info, .app, "Two")
        try? await Task.sleep(for: .milliseconds(5))
        #expect(live.lines.isEmpty)
    }

    @Test("it holds no more than its limit, the newest")
    func limit() async {
        let (log, live) = Self.setup(limit: 2)
        live.start()
        for number in 1...5 {
            log.log(.info, .app, "\(number)")
        }
        #expect(await eventually { Self.messages(live) == ["4", "5"] })
        live.stop()
    }

    @Test("pausing holds what is shown and counts what comes; the log goes on")
    func pauses() async {
        let (log, live) = Self.setup()
        live.start()
        log.log(.info, .app, "One")
        #expect(await eventually { Self.messages(live) == ["One"] })
        live.isPaused = true
        log.log(.info, .app, "Two")
        #expect(await eventually { live.linesWhilePaused == 1 })
        #expect(Self.messages(live) == ["One"])
        #expect(log.read().contains("Two"))
        live.isPaused = false
        #expect(Self.messages(live) == ["One", "Two"])
        #expect(live.linesWhilePaused == 0)
        live.stop()
    }

    @Test("a filter narrows what is shown, says how much it hides, and tells when it changes")
    func filters() async {
        let (log, live) = Self.setup()
        var changes: [LogFilter] = []
        live.onFilterChange = { changes.append($0) }
        log.log(.error, .connection, "Failed")
        log.log(.info, .app, "Started")
        live.start()
        #expect(live.totalCount == 2)
        live.filter = LogFilter(levels: [.error])
        #expect(Self.messages(live) == ["Failed"])
        #expect(live.totalCount == 2)
        #expect(changes == [LogFilter(levels: [.error])])
        log.log(.info, .app, "Hidden")
        log.log(.error, .audio, "Shown")
        #expect(await eventually { Self.messages(live) == ["Failed", "Shown"] })
        #expect(live.totalCount == 4)
        live.stop()
    }

    @Test("the text to copy is what is shown, and clearing empties it")
    func copies() async {
        let (log, live) = Self.setup()
        log.log(.error, .connection, "Failed")
        log.log(.info, .app, "Started")
        live.start()
        live.filter = LogFilter(levels: [.error])
        #expect(live.text == "1970-01-01T00:00:00Z ERROR connection: Failed\n")
        live.clear()
        #expect(live.lines.isEmpty)
        #expect(live.totalCount == 0)
        live.stop()
    }
}
