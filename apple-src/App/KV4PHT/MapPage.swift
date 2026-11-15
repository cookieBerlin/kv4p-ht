import KV4PAPRS
import KV4PPersistence
import KV4PProtocol
import KV4PRadio
import MapKit
import SwiftUI

/// The memories with a position and the APRS stations heard on a map, or as a list by distance (ADR-0068). The map
/// does not follow our position; the button of the system centres it.
struct MapPage: View {
    @Bindable var model: RadioViewModel
    @State private var camera = MapCameraPosition.automatic
    @State private var selected: MapSelection?
    @State private var isOnScreen = false
    @State private var isShowingLayers = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isPageOnScreen) private var isPageOnScreen

    var body: some View {
        Group {
            if model.isMapShownAsList, model.mapPoints.isEmpty, model.mapStations.isEmpty {
                ContentUnavailableView(
                    "Nothing on the map",
                    systemImage: "map",
                    description: Text("Memories with a position and APRS stations show here; the layers choose which.")
                        .foregroundStyle(Color.strongSecondary)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.isMapShownAsList {
                list
            } else {
                map
            }
        }
        // Over the map or the list, which take the full height beneath them. Outside the map, as the Mac's
        // VoiceOver does not see what the map holds in its own margins; the card of a marker comes above them.
        .floatingControls { controls }
        .safeAreaInset(edge: .top, alignment: .leading) {
            SlidingSwitch(
                "Show as",
                selection: $model.isMapShownAsList,
                options: [
                    .init(value: false, title: "Map", symbol: "map"),
                    // Numbered, as the list is in order of distance; the plain list stands for the memories.
                    .init(value: true, title: "List", symbol: "list.number"),
                ]
            ).padding([.leading, .top], 16)
        }
        .onAppear {
            isOnScreen = true
            updateVisibility()
            frame()
        }
        .onDisappear {
            isOnScreen = false
            updateVisibility()
        }
        .onChange(of: scenePhase) { updateVisibility() }
        .onChange(of: isPageOnScreen) { updateVisibility() }
        // The points come and go with the memories, the layers and the band, and our position arrives once; the map
        // frames them anew until it is moved by hand, and does not follow our position.
        .onChange(of: model.mapPoints.map(\.id)) { frame() }
        .onChange(of: Set(model.mapStations.map(\.id))) { frame() }
        .onChange(of: model.ownPosition == nil) { frame() }
    }

    private func updateVisibility() {
        model.isMapVisible = isOnScreen && isPageOnScreen && scenePhase == .active
    }

    /// All points and our position, until the map is moved by hand, or `always`, as *Show all* asks.
    private func frame(always: Bool = false) {
        guard always || !camera.positionedByUser, let frame = model.mapFrame else { return }
        camera = .region(
            MKCoordinateRegion(
                center: frame.center.coordinate,
                span: MKCoordinateSpan(latitudeDelta: frame.latitudeDelta, longitudeDelta: frame.longitudeDelta)
            )
        )
    }

    /// The buttons floating over the map or the list: the layers, *Show all* on the map, and on a phone the button for
    /// our position where its access is still open.
    @ViewBuilder private var controls: some View {
        if model.offersDistances {
            Button("Show my position", systemImage: "location") { model.askForDistances() }
                .floatingButton()
                .help("Show my position")
        }
        if !model.isMapShownAsList {
            Button("Show all", systemImage: "dot.viewfinder") {
                withAnimation { frame(always: true) }
            }
            .floatingButton()
            .disabled(model.mapFrame == nil)
            .help("Show all")
            .accessibilityIdentifier("map-show-all")
        }
        Button("Layers", systemImage: "square.3.layers.3d") { isShowingLayers = true }
            .floatingButton()
            .help("Layers")
            .choicePanel(
                "Layers",
                identifier: "map-layers",
                isPresented: $isShowingLayers,
                macHeight: model.isAPRSEnabled ? 400 : 300,
                arrowEdge: .bottom
            ) {
                MapLayers(model: model)
            }
    }

    private var map: some View {
        Map(position: $camera, selection: $selected) {
            if model.showsOwnPosition {
                UserAnnotation()
            }
            ForEach(model.mapPoints) { point in
                Marker(point.memory.name, monogram: Text(point.mark), coordinate: point.point.coordinate)
                    .tint(point.memory.kind.mapColor)
                    .tag(MapSelection.memory(point.id))
            }
            ForEach(model.mapStations) { station in
                Annotation(station.name, coordinate: station.point.coordinate) {
                    Button {
                        selected = .station(station.id)
                    } label: {
                        StationMark(station: station)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(station.name)
                }
            }
        }
        .mapControls {
            if model.showsOwnPosition {
                MapUserLocationButton()
            }
            MapCompass()
            MapScaleView()
        }
        .safeAreaInset(edge: .bottom) {
            switch selected {
            case .memory(let id):
                if let point = model.mapPoints.first(where: { $0.id == id }) {
                    MapPointCard(model: model, point: point) { selected = nil }.padding()
                }
            case .station(let id):
                if let station = model.mapStations.first(where: { $0.id == id }) {
                    MapStationCard(model: model, station: station) { selected = nil }.padding()
                }
            case nil: EmptyView()
            }
        }
        .accessibilityLabel("Map of the memories and stations")
        .accessibilityIdentifier("map")
    }

    private var list: some View {
        List {
            if !model.mapPoints.isEmpty {
                Section {
                    ForEach(model.mapPoints) { point in
                        MapPointRow(model: model, point: point)
                    }
                } header: {
                    Text("Memories").foregroundStyle(Color.strongSecondary)
                }
            }
            if !model.mapStations.isEmpty {
                Section {
                    ForEach(model.mapStations) { station in
                        MapStationRow(model: model, station: station)
                    }
                } header: {
                    Text("APRS stations").foregroundStyle(Color.strongSecondary)
                }
            }
        }
        .accessibilityLabel("Memories and stations by distance")
        .accessibilityIdentifier("map-list")
    }
}

/// What is chosen on the map: a memory by its id, or a station by its callsign or object name.
private enum MapSelection: Hashable {
    case memory(Int32)
    case station(String)
}

/// The symbol of a station on the map, on a disc that stands out from the map.
private struct StationMark: View {
    let station: MapStation

    var body: some View {
        Group {
            if let symbol = station.event.symbol {
                APRSSymbolView(symbol: symbol)
            } else {
                Image(systemName: "mappin")
            }
        }
        .padding(5)
        .background(.background, in: .circle)
        .overlay(Circle().stroke(.secondary))
    }
}

/// A station on the map, chosen with a tap: what it is, when it was heard, how far, and its packets or a chat.
private struct MapStationCard: View {
    let model: RadioViewModel
    let station: MapStation
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(station.name).font(.headline)
                Spacer()
                Button("Close", systemImage: "xmark", action: close).labelStyle(.iconOnly)
            }
            MapStationDetails(model: model, station: station)
            HStack {
                Button("Packets") { Task { await model.showPackets(of: station) } }
                if model.offersChat(with: station) {
                    Button("Chat") { model.openChat(with: station.event.fromCallsign) }
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
    }
}

/// A station of the list by distance; a tap shows its packets.
private struct MapStationRow: View {
    let model: RadioViewModel
    let station: MapStation

    var body: some View {
        Button {
            Task { await model.showPackets(of: station) }
        } label: {
            HStack {
                StationMark(station: station).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(station.name)
                    MapStationDetails(model: model, station: station)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // One text for the whole row, which stays a button.
        .accessibilityLabel(model.spokenStation(station))
        .accessibilityHint("Shows its packets")
    }
}

/// The kind, the time heard, the distance and the comment of a station on the map.
private struct MapStationDetails: View {
    let model: RadioViewModel
    let station: MapStation

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(
                ([station.event.typeName, station.heard.formatted(.relative(presentation: .named))]
                    + model.distanceText(station.distanceMeters, station.direction)).joined(separator: " · ")
            )
            .font(.subheadline.monospacedDigit())
            if let comment = station.event.comment, !comment.isEmpty {
                Text(comment).font(.footnote)
            }
        }
        .foregroundStyle(Color.strongSecondary)
    }
}

/// A memory on the map, chosen with a tap: what it is, how far, and tuning to it.
private struct MapPointCard: View {
    let model: RadioViewModel
    let point: MapPoint
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(point.memory.name).font(.headline)
                Spacer()
                Button("Close", systemImage: "xmark", action: close).labelStyle(.iconOnly)
            }
            MapPointDetails(model: model, point: point)
            if point.isTunable {
                Button("Tune") { Task { await model.tune(to: point.memory) } }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
    }
}

/// A memory of the list by distance; a tap tunes to it where it can.
private struct MapPointRow: View {
    let model: RadioViewModel
    let point: MapPoint

    var body: some View {
        Button {
            Task { await model.tune(to: point.memory) }
        } label: {
            HStack {
                MemoryKindSymbol(kind: point.memory.kind)
                VStack(alignment: .leading, spacing: 2) {
                    Text(point.memory.name)
                    MapPointDetails(model: model, point: point)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!point.isTunable)
        // One text for the whole row, which stays a button.
        .accessibilityLabel(model.spokenPoint(point))
        .accessibilityHint(point.isTunable ? "Tunes to it" : "")
    }
}

/// The frequency, the distance and the comment of a memory on the map.
private struct MapPointDetails: View {
    let model: RadioViewModel
    let point: MapPoint

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(
                ([model.shown(point.memory.frequency) + " MHz"] + point.bandText
                    + model.distanceText(point.distanceMeters, point.direction))
                    .joined(separator: " · ")
            )
            .font(.subheadline.monospacedDigit())
            if !point.memory.comment.isEmpty {
                Text(point.memory.comment).font(.footnote)
            }
        }
        .foregroundStyle(Color.strongSecondary)
    }
}

extension RadioViewModel {
    /// The distance and direction of a place, where our position is known.
    fileprivate func distanceText(_ distance: Double?, _ direction: CompassPoint?) -> [String] {
        guard let distance else { return [] }
        return [
            [units.distance(meters: distance, locale: .current), direction?.label].compactMap(\.self).joined(
                separator: " "
            )
        ]
    }

    /// What VoiceOver reads for a point: the memory as in its list, and how far it is.
    fileprivate func spokenPoint(_ point: MapPoint) -> String {
        ([spokenRow(point.memory, withComment: false)] + point.bandText
            + distanceText(point.distanceMeters, point.direction)
            + (point.memory.comment.isEmpty ? [] : [point.memory.comment])).joined(separator: ", ")
    }

    /// What VoiceOver reads for a station: its name and kind, when it was heard, how far, and its comment.
    fileprivate func spokenStation(_ station: MapStation) -> String {
        ([station.name, station.event.typeName, "heard " + station.heard.formatted(.relative(presentation: .named))]
            + distanceText(station.distanceMeters, station.direction) + [station.event.comment ?? ""])
            .filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// A station can chat, but not an object, and not our own station.
    fileprivate func offersChat(with station: MapStation) -> Bool {
        station.event.kind != .object && station.event.fromCallsign.uppercased() != callsign.uppercased()
    }
}

extension MapPoint {
    /// What a marker holds: its band, so that both stand apart where both are shown; a dot for another band.
    fileprivate var mark: String {
        switch module {
        case .sa818VHF: "2m"
        case .sa818UHF: "70"
        case nil: "•"
        }
    }

    /// The band, where one of the radio's.
    fileprivate var bandText: [String] { module.map { [$0.band] } ?? [] }
}

extension MapStation {
    /// When it was last heard.
    fileprivate var heard: Date { Date(timeIntervalSince1970: Double(event.lastSeenMs) / 1000) }
}

/// What the map shows: the kinds of memory, by colour, the band and the APRS stations.
private struct MapLayers: View {
    @Bindable var model: RadioViewModel

    var body: some View {
        Group {
            Section {
                ForEach(MemoryKind.allCases, id: \.self) { kind in
                    Toggle(isOn: shows(MapLayer(kind))) {
                        Label {
                            // Named as well, for those who cannot tell the colours apart.
                            Text("\(MapLayer(kind).title) (\(kind.mapColorName))")
                        } icon: {
                            Image(systemName: "circle.fill").foregroundStyle(kind.mapColor)
                        }
                    }
                }
            } header: {
                Text("Kind, by colour").foregroundStyle(Color.strongSecondary)
            }
            Section {
                Picker("Band", selection: $model.mapBand) {
                    ForEach(MapBand.allCases, id: \.self) { band in
                        Text(band.title).tag(band)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Band, marked 2m or 70").foregroundStyle(Color.strongSecondary)
            }
            if model.isAPRSEnabled {
                Section {
                    Toggle(MapLayer.stations.title, isOn: shows(.stations))
                    Picker("Heard within", selection: $model.mapStationWindow) {
                        ForEach(MapStationWindow.allCases, id: \.self) { window in
                            Text(window.title).tag(window)
                        }
                    }
                } header: {
                    Text("APRS, by symbol").foregroundStyle(Color.strongSecondary)
                }
            }
        }

    }

    private func shows(_ layer: MapLayer) -> Binding<Bool> {
        Binding(
            get: { model.mapLayers.contains(layer) },
            set: { isOn in
                if isOn { model.mapLayers.insert(layer) } else { model.mapLayers.remove(layer) }
            }
        )
    }
}

extension MemoryKind {
    /// The colour of its markers, and its name for the layers. Darker than the system's colours, on which MapKit's white
    /// mark of the band would be too faint: at least 5:1 against it, in light and dark alike.
    fileprivate var mapColor: Color {
        switch self {
        case .repeater: Color(red: 0x00 / 255, green: 0x58 / 255, blue: 0xD0 / 255)
        case .frequency: Color(red: 0x1A / 255, green: 0x7F / 255, blue: 0x37 / 255)
        case .beacon: Color(red: 0xB5 / 255, green: 0x4A / 255, blue: 0x00 / 255)
        }
    }

    fileprivate var mapColorName: String {
        switch self {
        case .repeater: "blue"
        case .frequency: "green"
        case .beacon: "orange"
        }
    }
}

extension GeoPoint {
    fileprivate var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
