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

/// The log and what can be done with it (ADR-0059).
struct LoggingSettings: View {
    @Bindable var model: RadioViewModel
    @State private var summary: LogSummary?
    @State private var isConfirmingDelete = false

    var body: some View {
        Form {
            Section("Log") {
                if let live = model.liveLog {
                    NavigationLink("Live log") { LiveLogView(model: model, live: live) }
                }
                if let summary {
                    LabeledContent(
                        "Stored",
                        value: summary.since.map { "\(Self.size(summary)), since \($0)" } ?? Self.size(summary)
                    )
                }
                Toggle("Detailed logging", isOn: $model.isDetailedLogging)
                    .explained(ControlHelp.detailedLogging)
                if let ends = model.detailedLoggingEnds {
                    LabeledContent("Ends") { Text(ends, format: .dateTime.day().month().hour().minute()) }
                }
            }
            ProblemReportSection(model: model)
            Section {
                Button("Delete the log and crash data…", role: .destructive) { isConfirmingDelete = true }
            }
        }
        .task { summary = model.logSummary }
        .alert("Delete the log and crash data?", isPresented: $isConfirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                model.deleteDiagnostics()
                summary = model.logSummary
            }
        }
    }

    private static func size(_ summary: LogSummary) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(summary.byteCount), countStyle: .file)
    }
}

/// A report on a problem, which the user sees before it goes anywhere.
struct ProblemReportSection: View {
    let model: RadioViewModel
    @State private var report = ""
    @State private var file: URL?

    var body: some View {
        Section("Report a problem") {
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
        .task { prepare() }
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
        .task { prepare() }
    }

    /// The file for the share dialog; a temporary one, which the system removes.
    private func prepare() {
        report = model.problemReport(in: .current)
        let url = URL.temporaryDirectory.appending(path: ProblemReport.fileName)
        file = (try? report.write(to: url, atomically: true, encoding: .utf8)) == nil ? nil : url
    }
}

/// The report on its own, after the app has asked about a crash.
struct ProblemReportSheet: View {
    let model: RadioViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form { ProblemReportSection(model: model) }
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
        }
        #if os(macOS)
            .frame(minWidth: 480, minHeight: 420)
        #endif
    }
}

/// What is being logged, as it happens.
struct LiveLogView: View {
    let model: RadioViewModel
    @Bindable var live: LiveLog
    @State private var position = ScrollPosition(edge: .bottom)
    @State private var isAtEnd = true

    var body: some View {
        VStack(spacing: 0) {
            controls
            if !live.filter.isEmpty {
                filterNotice
            }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(live.lines) { row($0) }
                }
                .padding(8)
                .scrollTargetLayout()
            }
            .scrollPosition($position)
            .defaultScrollAnchor(.bottom)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 40
            } action: { _, atEnd in
                isAtEnd = atEnd
            }
            .onChange(of: live.lines.last?.id) {
                if isAtEnd { position.scrollTo(edge: .bottom) }
            }
            .overlay(alignment: .bottom) {
                if !isAtEnd {
                    Button("New lines", systemImage: "arrow.down") { position.scrollTo(edge: .bottom) }
                        .buttonStyle(.borderedProminent)
                        .padding(8)
                }
            }
            .overlay {
                if live.lines.isEmpty {
                    ContentUnavailableView("Nothing to show", systemImage: "doc.text.magnifyingglass")
                }
            }
        }
        .navigationTitle("Live log")
        .onAppear { live.start() }
        .onDisappear { live.stop() }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            TextField("Search", text: $live.filter.search, prompt: Text("Search"))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
            Menu {
                ForEach(DiagnosticLog.Level.allCases, id: \.self) { level in
                    Toggle(Self.name(of: level), isOn: membership(of: level, in: \.levels))
                }
            } label: {
                Label(
                    "Levels",
                    systemImage: live.filter.levels.isEmpty ? "exclamationmark.circle" : "exclamationmark.circle.fill"
                )
                .labelStyle(.iconOnly)
            }
            .fixedSize()
            Menu {
                ForEach(DiagnosticLog.Category.allCases, id: \.self) { category in
                    Toggle(category.rawValue.capitalized, isOn: membership(of: category, in: \.categories))
                }
            } label: {
                Label(
                    "Categories",
                    systemImage: live.filter.categories.isEmpty
                        ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
                )
                .labelStyle(.iconOnly)
            }
            .fixedSize()
            Button(
                live.isPaused ? "Continue" : "Pause",
                systemImage: live.isPaused ? "play.fill" : "pause.fill"
            ) {
                live.isPaused.toggle()
            }
            .labelStyle(.iconOnly)
            Button("Copy what is shown", systemImage: "doc.on.doc") { copy() }
                .labelStyle(.iconOnly)
        }
        .padding(8)
    }

    /// A remembered filter hides lines from the start, so it says so.
    private var filterNotice: some View {
        HStack {
            Label(
                "Filter on: \(live.lines.count) of \(live.totalCount) lines",
                systemImage: "line.3.horizontal.decrease"
            )
            .font(.footnote)
            Spacer()
            Button("Clear") { live.filter = LogFilter() }
                .font(.footnote)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    private func membership<Value: Hashable>(
        of value: Value,
        in path: WritableKeyPath<LogFilter, Set<Value>>
    ) -> Binding<Bool> {
        Binding {
            live.filter[keyPath: path].contains(value)
        } set: { isOn in
            if isOn {
                live.filter[keyPath: path].insert(value)
            } else {
                live.filter[keyPath: path].remove(value)
            }
        }
    }

    private func row(_ line: LogLine) -> some View {
        let time = Text(line.date, format: .dateTime.hour().minute().second()).foregroundStyle(.secondary)
        let category = Text(line.category.rawValue).foregroundStyle(.secondary)
        let message = Text(line.message).foregroundStyle(Self.color(of: line.level))
        return Text("\(time) \(category) \(message)")
            .font(.caption.monospaced())
            .textSelection(.enabled)
    }

    private static func color(of level: DiagnosticLog.Level) -> Color {
        switch level {
        case .error: .red
        case .info: .primary
        case .detail: .secondary
        }
    }

    private static func name(of level: DiagnosticLog.Level) -> String {
        switch level {
        case .error: "Errors"
        case .info: "Info"
        case .detail: "Details"
        }
    }

    private func copy() {
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(model.liveLogText(), forType: .string)
        #else
            UIPasteboard.general.string = model.liveLogText()
        #endif
    }
}
