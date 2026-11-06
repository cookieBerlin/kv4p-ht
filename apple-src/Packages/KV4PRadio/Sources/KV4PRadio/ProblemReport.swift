import Foundation
import KV4PAPRS

/// What the user can send about a problem (ADR-0059): they see it first, and nothing leaves the device without them.
public enum ProblemReport {
    public struct Environment: Equatable, Sendable {
        public let version: String
        public let device: String
        public let system: String

        public init(version: String, device: String, system: String) {
            self.version = version
            self.device = device
            self.system = system
        }
    }

    public static let fileName = "kv4p-problem-report.txt"

    private static func summary(_ environment: Environment, firmware: String) -> String {
        """
        App: \(environment.version)
        Device: \(environment.device)
        System: \(environment.system)
        Firmware: \(firmware)
        """
    }

    public static func text(
        environment: Environment,
        firmware: String,
        log: String,
        crashes: [String],
        callsign: String
    ) -> String {
        let crashText = crashes.isEmpty ? "Crashes: none reported" : "Crashes:\n" + crashes.joined(separator: "\n")
        return redacted(
            """
            \(summary(environment, firmware: firmware))

            \(crashText)

            Log:
            \(log)
            """,
            callsign: callsign
        )
    }

    /// The log holds no callsigns, but what else a report takes in might.
    public static func redacted(_ text: String, callsign: String) -> String {
        let base = APRSEvent.baseCallsign(callsign)
        guard !base.isEmpty else { return text }
        return text.replacingOccurrences(
            of: "\\b\(NSRegularExpression.escapedPattern(for: base))\\b",
            with: "[callsign]",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    /// A prepared issue on the project's page, without the log, which the user attaches after looking at it. Issues are
    /// public.
    public static func issueURL(environment: Environment, firmware: String) -> URL? {
        var components = URLComponents(string: AboutInfo.sourceAddress + "/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "title", value: "Problem: "),
            URLQueryItem(
                name: "body",
                value: """
                    **What happened?**


                    **What did you expect?**


                    **Attach the report file here, after looking through it. Issues are public.**

                    \(summary(environment, firmware: firmware))
                    """
            ),
        ]
        return components?.url
    }
}
