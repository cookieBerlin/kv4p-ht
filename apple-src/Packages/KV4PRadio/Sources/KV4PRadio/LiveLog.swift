import Foundation
import Observation

/// The lines of the log for the live view (ADR-0059): the end of what is stored, then what comes. It only works while
/// the view is open, and only holds a limited part; the files stay what a report is made from.
@MainActor
@Observable
public final class LiveLog {
    /// What the view shows, oldest first.
    public private(set) var lines: [LogLine] = []
    /// All it holds, also what the filter hides.
    public private(set) var totalCount = 0
    /// New lines since the view was paused.
    public private(set) var linesWhilePaused = 0
    public var filter = LogFilter() {
        didSet {
            show()
            onFilterChange?(filter)
        }
    }
    public var isPaused = false {
        didSet {
            linesWhilePaused = 0
            show()
        }
    }
    /// So that a filter is remembered.
    @ObservationIgnored public var onFilterChange: ((LogFilter) -> Void)?

    @ObservationIgnored private let diagnostics: DiagnosticLog
    @ObservationIgnored private let limit: Int
    @ObservationIgnored private let initialLines: Int
    @ObservationIgnored private let showInterval: Duration
    @ObservationIgnored private var all: [LogLine] = []
    @ObservationIgnored private var waiting: [LogLine] = []
    @ObservationIgnored private var nextId = 0
    @ObservationIgnored private var reader: Task<Void, Never>?
    @ObservationIgnored private var shower: Task<Void, Never>?

    public init(
        diagnostics: DiagnosticLog,
        limit: Int = 2_000,
        initialLines: Int = 500,
        showInterval: Duration = .milliseconds(250)
    ) {
        self.diagnostics = diagnostics
        self.limit = limit
        self.initialLines = initialLines
        self.showInterval = showInterval
    }

    public func start() {
        guard reader == nil else { return }
        let stored = diagnostics.read().split(separator: "\n").suffix(initialLines)
        add(stored.compactMap { LogLine(parsing: String($0)) })
        show()
        let lines = diagnostics.liveLines()
        reader = Task { [weak self] in
            for await line in lines {
                self?.waiting.append(line)
            }
        }
        let interval = showInterval
        // Gathered, as a busy feed could otherwise keep the screen from anything else.
        shower = Task { [weak self] in
            while (try? await Task.sleep(for: interval)) != nil {
                self?.showWaiting()
            }
        }
    }

    public func stop() {
        reader?.cancel()
        reader = nil
        shower?.cancel()
        shower = nil
        clear()
    }

    public func clear() {
        all = []
        waiting = []
        linesWhilePaused = 0
        show()
    }

    /// What is shown, as the file holds it.
    public var text: String {
        lines.map { $0.text + "\n" }.joined()
    }

    private func showWaiting() {
        guard !waiting.isEmpty else { return }
        let new = waiting
        waiting = []
        add(new)
        if isPaused {
            linesWhilePaused += new.count
            totalCount = all.count
        } else {
            show()
        }
    }

    private func add(_ new: [LogLine]) {
        for var line in new {
            line.id = nextId
            nextId += 1
            all.append(line)
        }
        all.removeFirst(max(0, all.count - limit))
    }

    private func show() {
        totalCount = all.count
        lines = all.filter(filter.matches)
    }
}
