import KV4PRadio
import SwiftUI

extension ProblemReport.Environment {
    /// This app on this device.
    static var current: Self {
        var size = 0
        #if os(macOS)
            let key = "hw.model"
            let platform = "macOS"
        #else
            let key = "hw.machine"
            let platform = "iOS"
        #endif
        sysctlbyname(key, nil, &size, nil, 0)
        var name = [CChar](repeating: 0, count: size)
        sysctlbyname(key, &name, &size, nil, 0)
        return Self(
            version: AboutInfo(info: Bundle.main.infoDictionary ?? [:]).version,
            device: String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self),
            system: "\(platform) \(ProcessInfo.processInfo.operatingSystemVersionString)"
        )
    }
}

/// A report on a problem, which the user sees before it goes anywhere (ADR-0059).
struct ProblemReportView: View {
    @Bindable var model: RadioViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var report = ""
    @State private var file: URL?
    @State private var isConfirmingDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Report") {
                    Text(
                        "The report holds the app and system versions, the device type, the firmware, the app's log and crash data. Your callsign is replaced. Nothing leaves this device unless you send it."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    NavigationLink("Show the report") { reportText }
                    if let file {
                        ShareLink("Share the report…", item: file)
                    }
                    if let issue = model.problemIssueURL(in: .current) {
                        Link("Open a GitHub issue", destination: issue)
                        Text("Issues are public. Look through the report before you attach it there.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Log") {
                    Toggle("Detailed logging", isOn: $model.isDetailedLogging)
                        .explained(ControlHelp.detailedLogging)
                    Button("Delete the log and crash data…", role: .destructive) { isConfirmingDelete = true }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Report a problem")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: model.isDetailedLogging) { prepare() }
            .alert("Delete the log and crash data?", isPresented: $isConfirmingDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    model.deleteDiagnostics()
                    prepare()
                }
            }
        }
        #if os(macOS)
            .frame(minWidth: 480, minHeight: 420)
        #endif
    }

    private var reportText: some View {
        ScrollView {
            Text(report)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("Report")
    }

    /// The file for the share dialog; a temporary one, which the system removes.
    private func prepare() {
        report = model.problemReport(in: .current)
        let url = URL.temporaryDirectory.appending(path: ProblemReport.fileName)
        file = (try? report.write(to: url, atomically: true, encoding: .utf8)) == nil ? nil : url
    }
}
