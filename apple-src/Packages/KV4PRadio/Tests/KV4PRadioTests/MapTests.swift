import Foundation
import KV4PPersistence
import KV4PSimulator
import KV4PTestSupport
import Synchronization
import Testing

@testable import KV4PProtocol
@testable import KV4PRadio

/// The map: its switch, its layers, the memories on it and what it shows first (ADR-0068).
@MainActor
@Suite("Map")
struct MapTests {
    private final class CountingLocation: LocationProvider {
        private let reads = Mutex(0)
        var count: Int { reads.withLock { $0 } }

        func currentLocation() async -> GeoPoint? {
            reads.withLock { $0 += 1 }
            return MapTests.here
        }
    }

    nonisolated static let here = GeoPoint(latitude: 49, longitude: -72)
    private static let degreeOnEarth = 111_195.0

    static let near = ChannelMemory(
        name: "Near repeater",
        frequency: 145.6,
        offset: .down,
        kind: .repeater,
        latitude: 49.1,
        longitude: -72
    )
    static let far = ChannelMemory(
        name: "Far repeater",
        frequency: 145.7,
        offset: .down,
        kind: .repeater,
        latitude: 50,
        longitude: -72
    )
    static let beacon = ChannelMemory(name: "Beacon", frequency: 144.49, kind: .beacon, latitude: 49, longitude: -71)
    static let meeting = ChannelMemory(name: "Meeting", frequency: 145.5, latitude: 48.5, longitude: -72)
    static let nowhere = ChannelMemory(name: "Nowhere", frequency: 145.55, kind: .repeater)
    static let sixMetres = ChannelMemory(
        name: "6 m repeater",
        frequency: 50.5,
        kind: .repeater,
        latitude: 49.3,
        longitude: -72
    )
    static let uhf = ChannelMemory(
        name: "UHF repeater",
        frequency: 439.1,
        offset: .down,
        offsetKHz: 7600,
        kind: .repeater,
        latitude: 49.2,
        longitude: -72
    )

    private static func model(
        _ memories: [ChannelMemory] = [],
        location: (any LocationProvider)? = nil,
        permissions: FakePermissions = FakePermissions()
    ) async throws -> RadioViewModel {
        let repository = try SwiftDataMemoryRepository.inMemory()
        _ = try await repository.insert(memories)
        let model = RadioViewModel(
            makeController: { _, rxAudio in
                let clock = ManualClock()
                let transport = SimulatorTransport(simulator: RadioSimulator(scenario: .ble), clock: clock)
                return RadioController(transport: transport, clock: clock, rxAudio: rxAudio)
            },
            serialDevices: { [] },
            memories: repository,
            location: location,
            permissions: permissions
        )
        await model.loadMemories()
        return model
    }

    @Test("the map is on, shows repeaters and beacons as a map, and all of it stays on this device")
    func settings() throws {
        let defaults = AppSettings()
        #expect(defaults.isMapEnabled)
        #expect(defaults.mapLayers == [.repeaters, .beacons])
        #expect(!defaults.isMapShownAsList)
        #expect(defaults.mapBand == .radio)
        var settings = AppSettings()
        settings.isMapEnabled = false
        settings.mapLayers = [.frequencies]
        settings.isMapShownAsList = true
        settings.mapBand = .seventyCentimetres
        let decoded = AppSettings(data: try settings.encoded())
        #expect(!decoded.isMapEnabled)
        #expect(decoded.mapLayers == [.frequencies])
        #expect(decoded.isMapShownAsList)
        #expect(decoded.mapBand == .seventyCentimetres)
        #expect(SettingsSync.values(of: settings) == SettingsSync.values(of: AppSettings()))
        let store = MemorySettingsStore(settings)
        let model = RadioViewModelSettingsTests.model(store)
        #expect(!model.isMapEnabled)
        #expect(model.mapLayers == [.frequencies])
        #expect(model.isMapShownAsList)
        #expect(model.mapBand == .seventyCentimetres)
        model.mapBand = .all
        #expect(store.settings.mapBand == .all)
        model.isMapEnabled = true
        model.mapLayers = [.beacons]
        model.isMapShownAsList = false
        #expect(store.settings.isMapEnabled)
        #expect(store.settings.mapLayers == [.beacons])
        #expect(!store.settings.isMapShownAsList)
    }

    @Test(
        "each kind of memory has its layer",
        arguments: [
            (MemoryKind.repeater, MapLayer.repeaters, "Repeaters"),
            (.frequency, .frequencies, "Frequencies"),
            (.beacon, .beacons, "Beacons"),
        ]
    )
    func layers(kind: MemoryKind, layer: MapLayer, title: String) {
        #expect(MapLayer(kind) == layer)
        #expect(layer.title == title)
    }

    @Test(
        "the bands have short names",
        arguments: [
            (MapBand.radio, "Radio's band"), (.twoMetres, "2 m"), (.seventyCentimetres, "70 cm"), (.all, "All"),
        ]
    )
    func bandTitles(band: MapBand, title: String) {
        #expect(band.title == title)
    }

    @Test("each point knows the module that receives it, if any")
    func pointBand() async throws {
        let model = try await Self.model([Self.near, Self.uhf, Self.sixMetres])
        model.mapBand = .all
        #expect(model.mapPoints.map(\.module) == [.sa818VHF, .sa818UHF, nil])
    }

    @Test("without a radio, the radio's band is 2 m and 70 cm, and all brings the other bands too")
    func bandsWithoutRadio() async throws {
        let model = try await Self.model([Self.near, Self.uhf, Self.sixMetres])
        #expect(model.mapPoints.map(\.memory.name) == ["Near repeater", "UHF repeater"])
        model.mapBand = .twoMetres
        #expect(model.mapPoints.map(\.memory.name) == ["Near repeater"])
        model.mapBand = .seventyCentimetres
        #expect(model.mapPoints.map(\.memory.name) == ["UHF repeater"])
        model.mapBand = .all
        #expect(model.mapPoints.map(\.memory.name) == ["Near repeater", "UHF repeater", "6 m repeater"])
    }

    @Test("with a radio, the radio's band is the one it receives")
    func bandOfRadio() async throws {
        let model = try await Self.model([Self.near, Self.uhf, Self.sixMetres])
        await model.connect()
        #expect(await RadioViewModelTests.eventually(model) { $0.isReady && $0.snapshot.isInSync })
        #expect(model.mapPoints.map(\.memory.name) == ["Near repeater"])
        model.mapBand = .seventyCentimetres
        #expect(model.mapPoints.map(\.memory.name) == ["UHF repeater"])
    }

    @Test("the map shows the memories with a position on the layers that are on")
    func points() async throws {
        let model = try await Self.model([Self.meeting, Self.near, Self.nowhere, Self.beacon])
        #expect(model.mapPoints.map(\.memory.name) == ["Near repeater", "Beacon"])
        model.mapLayers = [.frequencies]
        #expect(model.mapPoints.map(\.memory.name) == ["Meeting"])
        #expect(model.mapPoints.first?.point == GeoPoint(latitude: 48.5, longitude: -72))
        #expect(model.mapPoints.first?.id == model.memories.first?.id)
        model.mapLayers = []
        #expect(model.mapPoints.isEmpty)
    }

    @Test("all groups are on the map, not only the one the list shows")
    func allGroups() async throws {
        var grouped = Self.near
        grouped.group = "Elsewhere"
        let model = try await Self.model([grouped, Self.beacon])
        model.selectedGroup = "Other"
        #expect(model.mapPoints.count == 2)
    }

    @Test("without our position, the points keep the order of the memories and have no distance")
    func withoutOwnPosition() async throws {
        let model = try await Self.model([Self.far, Self.near])
        #expect(model.mapPoints.map(\.memory.name) == ["Far repeater", "Near repeater"])
        #expect(model.mapPoints.allSatisfy { $0.distanceMeters == nil && $0.direction == nil })
    }

    @Test("with our position, the nearest comes first, with its distance and direction")
    func byDistance() async throws {
        let model = try await Self.model([Self.far, Self.beacon, Self.near], location: CountingLocation())
        model.isMapVisible = true
        #expect(await eventually { model.ownPosition != nil })
        #expect(model.mapPoints.map(\.memory.name) == ["Near repeater", "Beacon", "Far repeater"])
        let far = try #require(model.mapPoints.last)
        #expect(abs((far.distanceMeters ?? 0) - Self.degreeOnEarth) < 10)
        #expect(far.direction == .north)
    }

    @Test("our position is only read while the map is shown and access is granted")
    func readsOnlyWhenShown() async throws {
        let hidden = CountingLocation()
        _ = try await Self.model(location: hidden)
        await Task.yield()
        #expect(hidden.count == 0)

        let undecided = CountingLocation()
        let model = try await Self.model(location: undecided, permissions: FakePermissions([.location: .notDetermined]))
        model.isMapVisible = true
        await Task.yield()
        #expect(undecided.count == 0)
        #expect(model.offersDistances)

        let shown = CountingLocation()
        let visible = try await Self.model(location: shown)
        visible.isMapVisible = true
        #expect(await eventually { shown.count == 1 })
    }

    @Test("a memory tunes from the map once the radio is ready and receives it")
    func tunable() async throws {
        let model = try await Self.model([Self.near, Self.uhf])
        model.mapBand = .all
        #expect(model.mapPoints.allSatisfy { !$0.isTunable })
        await model.connect()
        #expect(await RadioViewModelTests.eventually(model) { $0.isReady && $0.snapshot.isInSync })
        #expect(model.mapPoints.map(\.isTunable) == [true, false])
    }

    @Test("without anything to show, the map has no frame of its own")
    func noFrame() async throws {
        #expect(MapFrame(around: []) == nil)
        #expect(try await Self.model([Self.nowhere]).mapFrame == nil)
    }

    @Test("one place is framed with a few kilometres around it")
    func onePlace() throws {
        let frame = try #require(MapFrame(around: [Self.here]))
        #expect(frame.center == Self.here)
        #expect(frame.latitudeDelta == MapFrame.smallestDelta)
        #expect(frame.longitudeDelta == MapFrame.smallestDelta)
    }

    @Test("several places are framed with a margin around them all")
    func severalPlaces() throws {
        let frame = try #require(
            MapFrame(around: [GeoPoint(latitude: 48, longitude: -73), GeoPoint(latitude: 50, longitude: -71)])
        )
        #expect(frame.center == GeoPoint(latitude: 49, longitude: -72))
        #expect(abs(frame.latitudeDelta - 2 * (1 + 2 * MapFrame.margin)) < 1e-9)
        #expect(abs(frame.longitudeDelta - 2 * (1 + 2 * MapFrame.margin)) < 1e-9)
    }

    @Test("the frame holds the points on the map and our position")
    func frameWithOwnPosition() async throws {
        let model = try await Self.model([Self.far], location: CountingLocation())
        #expect(model.mapFrame?.center == GeoPoint(latitude: 50, longitude: -72))
        model.isMapVisible = true
        #expect(await eventually { model.ownPosition != nil })
        #expect(model.mapFrame == MapFrame(around: [Self.far.position, Self.here].compactMap(\.self)))
    }

    @Test("a memory has a position only with both coordinates, and real numbers")
    func memoryPosition() {
        #expect(Self.near.position == GeoPoint(latitude: 49.1, longitude: -72))
        var memory = Self.near
        memory.longitude = nil
        #expect(memory.position == nil)
        memory.longitude = .nan
        #expect(memory.position == nil)
        memory = Self.near
        memory.latitude = nil
        #expect(memory.position == nil)
    }

    @Test("the demo has a repeater, a beacon and a frequency on the map")
    func demo() async throws {
        let model = try await Self.model()
        await model.loadDemoContent()
        #expect(await eventually { model.memories.count == DemoContent.memories.count })
        model.mapLayers = Set(MapLayer.allCases)
        #expect(Set(model.mapPoints.map(\.memory.kind)) == [.repeater, .beacon, .frequency])
    }
}
