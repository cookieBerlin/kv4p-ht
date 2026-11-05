import Foundation
import KV4PAPRS
import KV4PRadio
import SwiftUI
import UniformTypeIdentifiers

/// The icon after the text, for a link that leaves the app.
private struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.title
            configuration.icon
        }
    }
}

/// The text of an export, for the system's save dialog.
private struct ExportedText: FileDocument {
    static let readableContentTypes: [UTType] = [.plainText, .commaSeparatedText]

    let text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// The APRS packets with their search, filter and export (ADR-0057). The main page and the packets page of the settings
/// show the same; each has its own filter.
struct APRSPacketList: View {
    @Bindable var model: RadioViewModel
    let list: APRSList
    @State private var search = ""
    @State private var exported: ExportedText?
    @State private var exportFormat = APRSExport.Format.csv
    @State private var isExporting = false
    @State private var isOnScreen = false
    @Environment(\.scenePhase) private var scenePhase

    private var events: [APRSEvent] { model.aprsEvents(in: list) }
    private var filter: APRSListFilter { model.aprsFilter(in: list) }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            packets
        }
        .onAppear {
            search = filter.callsign
            isOnScreen = true
            updateVisibility()
        }
        .onDisappear {
            isOnScreen = false
            updateVisibility()
        }
        .onChange(of: scenePhase) { updateVisibility() }
        .onChange(of: search) {
            guard search != filter.callsign else { return }
            setFilter { $0.callsign = search }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exported,
            contentType: exportFormat == .csv ? .commaSeparatedText : .plainText,
            defaultFilename: exportFormat.fileName
        ) { _ in
            exported = nil
        }
    }

    private func updateVisibility() {
        let isVisible = isOnScreen && scenePhase == .active
        switch list {
        case .main: model.isAPRSVisible = isVisible
        case .packetsPage: model.isPacketsPageVisible = isVisible
        }
    }

    private func setFilter(_ change: (inout APRSListFilter) -> Void) {
        var changed = filter
        change(&changed)
        let list = list
        let model = model
        Task { await model.setAPRSFilter(changed, in: list) }
    }

    // MARK: Search, filter, export

    private var filterBar: some View {
        HStack(spacing: 8) {
            TextField("Callsign", text: $search, prompt: Text("Callsign"))
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                #endif
            Toggle(isOn: forMe) {
                Label("For me", systemImage: "person.crop.circle")
            }
            .toggleStyle(.button)
            .help(ControlHelp.forMe)
            typesMenu
            exportMenu
        }
        .labelStyle(.iconOnly)
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private var forMe: Binding<Bool> {
        Binding {
            filter.isForMe
        } set: { isOn in
            setFilter { $0.isForMe = isOn }
        }
    }

    private var typesMenu: some View {
        Menu {
            ForEach(APRSEvent.Kind.filterOptions, id: \.self) { kind in
                Toggle(kind.filterName, isOn: typeBinding(kind))
            }
        } label: {
            Label(
                "Types",
                systemImage: filter.kinds.isEmpty
                    ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
            )
        }
        .fixedSize()
        .help(ControlHelp.packetTypes)
    }

    private func typeBinding(_ kind: APRSEvent.Kind) -> Binding<Bool> {
        Binding {
            filter.kinds.contains(kind)
        } set: { isOn in
            setFilter {
                if isOn {
                    $0.kinds.insert(kind)
                } else {
                    $0.kinds.remove(kind)
                }
            }
        }
    }

    private var exportMenu: some View {
        Menu {
            ForEach(APRSExport.Format.allCases, id: \.self) { format in
                Button(format.label) { export(format) }
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .fixedSize()
        .help(ControlHelp.exportPackets)
    }

    private func export(_ format: APRSExport.Format) {
        Task {
            guard let text = await model.exportAPRS(format, from: list) else { return }
            exportFormat = format
            exported = ExportedText(text: text)
            isExporting = true
        }
    }

    // MARK: Packets

    private var packets: some View {
        List {
            if model.offersDistances {
                Button("Show distances", systemImage: "location") { model.askForDistances() }
            }
            ForEach(events) { event in
                row(event)
            }
            if model.hasMoreAPRSHistory(in: list) {
                Button("Load more", systemImage: "clock.arrow.circlepath") {
                    Task { await model.loadMoreAPRSHistory(in: list) }
                }
            }
        }
        .overlay {
            if events.isEmpty, !model.hasMoreAPRSHistory(in: list) {
                emptyState
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if filter.isEmpty {
            ContentUnavailableView(
                "No APRS packets yet",
                systemImage: "point.3.connected.trianglepath.dotted",
                description: Text("Tune to the APRS frequency of your region, e.g. 144.800 or 144.390 MHz.")
            )
        } else {
            ContentUnavailableView {
                Label("No packets fit the filter", systemImage: "line.3.horizontal.decrease.circle")
            } actions: {
                Button("Clear filter") {
                    search = ""
                    setFilter { $0 = APRSListFilter() }
                }
            }
        }
    }

    private func row(_ event: APRSEvent) -> some View {
        HStack(alignment: .top) {
            icon(event)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(Self.title(event)).font(.headline).strikethrough(event.isRemovedObject)
                    Spacer()
                    if let state = Self.delivery(event.deliveryState) {
                        Label(state.0, systemImage: state.1).labelStyle(.iconOnly).help(state.0)
                    }
                    if event.packetCount > 1 {
                        Text("×\(event.packetCount)").foregroundStyle(.secondary)
                    }
                    Text(Date(timeIntervalSince1970: Double(event.lastSeenMs) / 1000), style: Self.timeStyle(event))
                        .foregroundStyle(.secondary)
                    Menu {
                        Button("Delete", systemImage: "trash", role: .destructive) { model.deleteAPRSEvent(event) }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .contentShape(.rect)
                    }
                    .menuIndicator(.hidden)
                    .buttonStyle(.plain)
                    .fixedSize()
                    .accessibilityLabel("More for this packet")
                }
                if let text = event.text(units: model.units, locale: .current) {
                    Text(text).font(event.isRawText ? .footnote.monospaced() : .body)
                }
                if let caption = event.caption {
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                }
                if let position = model.position(of: event) {
                    location(position)
                }
            }
        }
        .textSelection(.enabled)
    }

    /// A packet's symbol, or what kind of packet it is. It tells more when looked at closer: a tooltip on the Mac, holding it
    /// on iPhone and iPad, as holding the text of the row selects it.
    private func icon(_ event: APRSEvent) -> some View {
        Group {
            if let symbol = event.symbol {
                APRSSymbolView(symbol: symbol)
            } else {
                Image(systemName: Self.symbol(event.kind)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 24)
        #if os(macOS)
            .help(event.details.joined(separator: "\n"))
        #else
            .contentShape(.rect)
            .contextMenu {
                ForEach(event.details, id: \.self) { Text($0) }
            }
        #endif
        .accessibilityLabel(event.details.joined(separator: ", "))
    }

    /// The coordinates lead to the map; the distance stands below them, as a phone has little room.
    @ViewBuilder private func location(_ position: StationPosition) -> some View {
        let coordinates = String(format: "%.5f, %.5f", position.point.latitude, position.point.longitude)
        if let map = position.mapURL {
            Link(destination: map) {
                Label(coordinates, systemImage: "arrow.up.right").labelStyle(TrailingIcon())
            }
            .font(.caption.monospacedDigit())
            .accessibilityLabel("Open \(coordinates) in Maps")
        }
        if let distance = position.distanceMeters {
            Text(
                [model.units.distance(meters: distance, locale: .current), position.direction?.label]
                    .compactMap(\.self).joined(separator: " ")
            )
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    /// A packet from another day says so, as a stored list goes back further than today.
    private static func timeStyle(_ event: APRSEvent) -> Text.DateStyle {
        Calendar.current.isDateInToday(Date(timeIntervalSince1970: Double(event.lastSeenMs) / 1000)) ? .time : .date
    }

    private static func delivery(_ state: APRSEvent.DeliveryState) -> (String, String)? {
        switch state {
        case .none: nil
        case .pending: ("Waiting for acknowledgement", "clock")
        case .delivered: ("Delivered", "checkmark.circle")
        case .rejected: ("Rejected", "xmark.circle")
        case .failed: ("Not delivered", "exclamationmark.triangle")
        }
    }

    private static func symbol(_ kind: APRSEvent.Kind) -> String {
        switch kind {
        case .message: "envelope"
        case .object: "flag"
        case .position: "mappin.and.ellipse"
        case .weather: "cloud.sun"
        case .status: "text.bubble"
        case .stationCapabilities: "antenna.radiowaves.left.and.right"
        case .unknown: "questionmark.circle"
        }
    }

    private static func title(_ event: APRSEvent) -> String {
        let from = event.fromCallsign
        switch event.kind {
        case .message: return "\(from) → \(event.toCallsign ?? "?")"
        case .object: return "\(event.objectName ?? "?") (\(from))"
        default: return event.relayCallsign.map { "\(from) via \($0)" } ?? from
        }
    }
}

/// The packets over the full height of the settings, to look through the history.
struct APRSPacketsPage: View {
    let model: RadioViewModel
    @State private var isConfirmingDeleteAll = false

    var body: some View {
        APRSPacketList(model: model, list: .packetsPage)
            .navigationTitle("Packets")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete all packets…", systemImage: "trash", role: .destructive) {
                        isConfirmingDeleteAll = true
                    }
                }
            }
            .alert("Delete all packets?", isPresented: $isConfirmingDeleteAll) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { model.deleteAllAPRSEvents() }
            } message: {
                Text("This removes all packets of the list, also those stored.")
            }
    }
}
