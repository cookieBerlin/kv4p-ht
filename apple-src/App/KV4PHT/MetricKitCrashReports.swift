import CryptoKit
import Foundation
import KV4PRadio
import MetricKit

/// Crash data from the system, for a report (ADR-0059). Forwarding only; the rules are in `RadioViewModel`.
@MainActor
final class MetricKitCrashReports {
    /// What a report holds of the system's data, without the region of the device.
    private struct CrashData: Encodable {
        let appVersion: String
        let appBuild: String
        let system: OSVersion
        let device: String
        let architecture: String
        let isTestFlight: Bool
        let from: Date
        let to: Date
        let result: DiagnosticResult
    }

    /// One for the whole app, as Apple asks: more would each get only some of the reports.
    private let manager = MetricManager()
    private var observer: Task<Void, Never>?

    init(model: RadioViewModel) {
        let reports = manager.diagnosticReports
        observer = Task { [weak model] in
            for await report in reports {
                guard case .crash = report.result, let json = Self.json(of: report) else { continue }
                // The same data gives the same id, so that a report that comes again is known.
                let id = SHA256.hash(data: Data(json.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
                model?.receiveCrashReport(id: id, json: json)
            }
        }
    }

    private static func json(of report: DiagnosticReport) -> String? {
        let data = CrashData(
            appVersion: report.environment.applicationVersion,
            appBuild: report.environment.applicationBuildVersion,
            system: report.environment.osVersion,
            device: report.environment.deviceType,
            architecture: report.environment.platformArchitecture,
            isTestFlight: report.environment.isTestFlightApp,
            from: report.timeRange.start,
            to: report.timeRange.end,
            result: report.result
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(data)).map { String(decoding: $0, as: UTF8.self) }
    }
}
