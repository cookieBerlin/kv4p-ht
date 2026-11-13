/// How long the app took to start, step by step, for one line of the log: what holds up the first frame shows there,
/// also without Instruments.
public struct LaunchTimes: Sendable {
    /// The steps in the order they were first measured; a step measured again adds to its time.
    private var steps: [(name: String, duration: Duration)] = []

    public init() {}

    public mutating func record(_ name: String, _ duration: Duration) {
        if let index = steps.firstIndex(where: { $0.name == name }) {
            steps[index].duration += duration
        } else {
            steps.append((name, duration))
        }
    }

    /// The time to the first frame, where the start of the process is known, then the steps, slowest first, in whole
    /// milliseconds.
    public func summary(firstFrameAfter firstFrame: Duration?) -> String {
        var parts: [String] = []
        if let firstFrame {
            parts.append("first frame after \(Self.milliseconds(firstFrame)) ms")
        }
        let slowestFirst = steps.sorted { $0.duration > $1.duration }
        if !slowestFirst.isEmpty {
            parts.append(slowestFirst.map { "\($0.name) \(Self.milliseconds($0.duration)) ms" }.joined(separator: ", "))
        }
        return "Launch: " + parts.joined(separator: "; ")
    }

    private static func milliseconds(_ duration: Duration) -> Int64 {
        let (seconds, attoseconds) = duration.components
        return seconds * 1_000 + (attoseconds + 500_000_000_000_000) / 1_000_000_000_000_000
    }
}
