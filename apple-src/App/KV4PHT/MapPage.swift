import KV4PPersistence
import KV4PProtocol
import KV4PRadio
import MapKit
import SwiftUI

/// The memories with a position on a map, or as a list by distance (ADR-0068). The map does not follow our position;
/// the button of the system centres it.
struct MapPage: View {
    @Bindable var model: RadioViewModel
    @State private var camera = MapCameraPosition.automatic
    @State private var selected: Int32?
    @State private var isOnScreen = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isPageOnScreen) private var isPageOnScreen

    var body: some View {
        VStack(spacing: 0) {
            controls
            if model.isMapShownAsList, model.mapPoints.isEmpty {
                ContentUnavailableView(
                    "Nothing on the map",
                    systemImage: "map",
                    description: Text("Memories with a position show here; the layers choose which.")
                )
            } else if model.isMapShownAsList {
                list
            } else {
                map
            }
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
        .onChange(of: model.ownPosition == nil) { frame() }
    }

    private func updateVisibility() {
        model.isMapVisible = isOnScreen && isPageOnScreen && scenePhase == .active
    }

    private func frame() {
        guard !camera.positionedByUser, let frame = model.mapFrame else { return }
        camera = .region(
            MKCoordinateRegion(
                center: frame.center.coordinate,
                span: MKCoordinateSpan(latitudeDelta: frame.latitudeDelta, longitudeDelta: frame.longitudeDelta)
            )
        )
    }

    /// Map or list, and the layers; on a phone, the button for our position where its access is still open.
    private var controls: some View {
        HStack {
            Picker("Show as", selection: $model.isMapShownAsList) {
                Text("Map").tag(false)
                Text("List").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
            if model.offersDistances {
                Button("Show my position", systemImage: "location") { model.askForDistances() }
                    .labelStyle(.iconOnly)
                    .help("Show my position")
            }
            Menu("Layers", systemImage: "square.3.layers.3d") {
                // A menu shows no colours of its own, so their names stand there.
                Section("Kind, by colour") {
                    ForEach(MapLayer.allCases, id: \.self) { layer in
                        Toggle("\(layer.title) (\(layer.colorName))", isOn: shows(layer))
                    }
                }
                Section("Band, marked 2m or 70") {
                    Picker("Band", selection: $model.mapBand) {
                        ForEach(MapBand.allCases, id: \.self) { band in
                            Text(band.title).tag(band)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .menuIndicator(.hidden)
            .capsuleMenu()
            .accessibilityIdentifier("map-layers")
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private func shows(_ layer: MapLayer) -> Binding<Bool> {
        Binding(
            get: { model.mapLayers.contains(layer) },
            set: { isOn in
                if isOn { model.mapLayers.insert(layer) } else { model.mapLayers.remove(layer) }
            }
        )
    }

    private var map: some View {
        Map(position: $camera, selection: $selected) {
            if model.showsOwnPosition {
                UserAnnotation()
            }
            ForEach(model.mapPoints) { point in
                Marker(point.memory.name, monogram: Text(point.mark), coordinate: point.point.coordinate)
                    .tint(MapLayer(point.memory.kind).color)
                    .tag(point.id)
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
            if let point = model.mapPoints.first(where: { $0.id == selected }) {
                MapPointCard(model: model, point: point) { selected = nil }
                    .padding()
            }
        }
        .accessibilityLabel("Map of the memories")
        .accessibilityIdentifier("map")
    }

    private var list: some View {
        List(model.mapPoints) { point in
            MapPointRow(model: model, point: point)
        }
        .accessibilityLabel("Memories by distance")
        .accessibilityIdentifier("map-list")
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
                ([model.shown(point.memory.frequency) + " MHz"] + point.bandText + model.distanceText(point))
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
    /// The distance and direction of a point, where our position is known.
    fileprivate func distanceText(_ point: MapPoint) -> [String] {
        guard let distance = point.distanceMeters else { return [] }
        return [
            [units.distance(meters: distance, locale: .current), point.direction?.label].compactMap(\.self)
                .joined(separator: " ")
        ]
    }

    /// What VoiceOver reads for a point: the memory as in its list, and how far it is.
    fileprivate func spokenPoint(_ point: MapPoint) -> String {
        ([spokenRow(point.memory, withComment: false)] + point.bandText + distanceText(point)
            + (point.memory.comment.isEmpty ? [] : [point.memory.comment])).joined(separator: ", ")
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

extension MapLayer {
    /// The colour of its markers, and its name for the menu.
    fileprivate var color: Color {
        switch self {
        case .repeaters: .blue
        case .frequencies: .green
        case .beacons: .orange
        }
    }

    fileprivate var colorName: String {
        switch self {
        case .repeaters: "blue"
        case .frequencies: "green"
        case .beacons: "orange"
        }
    }
}

extension GeoPoint {
    fileprivate var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
