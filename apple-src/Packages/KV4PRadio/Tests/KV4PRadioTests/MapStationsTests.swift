import Foundation
import KV4PAPRS
import KV4PPersistence
import KV4PTestSupport
import Testing

@testable import KV4PRadio

/// The APRS stations on the map: each at its last position, within a time window, also from the history (ADR-0068).
@MainActor
@Suite("Map stations")
struct MapStationsTests {
    nonisolated private static let minute: Int64 = 60_000
    private static let first = "N1CALL>APRS,TCPIP*:=4903.50N/07201.75W>Mobile"
    private static let second = "N2CALL>APRS,TCPIP*:=4904.50N/07202.75W>Second"
    private static let moved = "N1CALL>APRS,TCPIP*:=4905.50N/07201.75W>Moved"
    private static let status = "N3CALL>APRS,TCPIP*:>On the air"
    private static let own = "N0CALL>APRS,TCPIP*:=4903.50N/07201.75W>Own"
    private static let object = "N1CALL>APRS,TCPIP*:;OBJECT   *111111z4903.50N/07201.75W-Test object"
    private static let removed = "N1CALL>APRS,TCPIP*:;OBJECT   _111111z4903.50N/07201.75W-Test object"

    @MainActor
    private final class Setup {
        let link = FakeLink()
        let time = TestTime()
        let history: SwiftDataAPRSHistory
        let model: RadioViewModel

        init(listLimit: Int = 500, location: (any LocationProvider)? = nil) throws {
            history = try SwiftDataAPRSHistory.inMemory()
            var settings = AppSettings()
            settings.keepsInternetPackets = true
            time.advance(by: 10 * MapStationsTests.minute)
            let time = time
            model = RadioViewModel(
                makeController: { _, _ in RadioController(transport: ScriptedTransport()) },
                serialDevices: { [] },
                location: location,
                internet: link,
                aprsHistory: history,
                settings: MemorySettingsStore(settings),
                permissions: FakePermissions(),
                now: { time.ms },
                aprsListLimit: listLimit
            )
            model.callsign = "N0CALL"
        }

        /// A minute after the one before.
        func receive(_ line: String) async {
            let count = model.aprsEvents.count
            let last = model.aprsEvents.first?.lastSeenMs
            time.advance(by: MapStationsTests.minute)
            link.receive.yield(line)
            #expect(
                await eventually {
                    self.model.aprsEvents.count != count || self.model.aprsEvents.first?.lastSeenMs != last
                }
            )
        }

        var names: [String] { model.mapStations.map(\.name) }
    }

    @Test("the stations of the last hour are on by default, and the window stays on this device")
    func settings() throws {
        #expect(AppSettings().mapLayers.contains(.stations))
        #expect(AppSettings().mapStationWindow == .hour)
        var settings = AppSettings()
        settings.mapStationWindow = .day
        #expect(AppSettings(data: try settings.encoded()).mapStationWindow == .day)
        #expect(SettingsSync.values(of: settings) == SettingsSync.values(of: AppSettings()))
        let store = MemorySettingsStore(settings)
        let model = RadioViewModelSettingsTests.model(store)
        #expect(model.mapStationWindow == .day)
        model.mapStationWindow = .all
        #expect(store.settings.mapStationWindow == .all)
    }

    nonisolated private static let windowCases: [(MapStationWindow, String, Int64?)] = [
        (.quarterHour, "15 min", 15 * minute), (.hour, "1 h", 60 * minute), (.sixHours, "6 h", 6 * 60 * minute),
        (.day, "24 h", 24 * 60 * minute), (.all, "All", nil),
    ]

    @Test("the windows have short names and their length", arguments: windowCases)
    func windows(window: MapStationWindow, title: String, milliseconds: Int64?) {
        #expect(window.title == title)
        #expect(window.milliseconds == milliseconds)
        #expect(MapLayer.stations.title == "APRS stations")
    }

    @Test("each station is at its last position, and packets without one stay off the map")
    func lastPosition() async throws {
        let setup = try Setup()
        for line in [Self.first, Self.second, Self.moved, Self.status] {
            await setup.receive(line)
        }
        #expect(setup.names == ["N1CALL", "N2CALL"])
        let station = try #require(setup.model.mapStations.first)
        #expect(abs(station.point.latitude - 49.091_67) < 0.000_01)
        #expect(station.id == "N1CALL")
        #expect(station.event.comment == "Moved")
    }

    @Test("an object stands for itself, not for its sender, and goes once it is removed")
    func objects() async throws {
        let setup = try Setup()
        await setup.receive(Self.first)
        await setup.receive(Self.object)
        #expect(Set(setup.model.mapStations.map(\.id)) == ["N1CALL", "OBJECT"])
        await setup.receive(Self.removed)
        #expect(setup.model.mapStations.map(\.id) == ["N1CALL"])
    }

    @Test("only what was heard within the window is on the map")
    func window() async throws {
        let setup = try Setup()
        await setup.receive(Self.first)
        setup.time.advance(by: 20 * Self.minute)
        setup.model.mapStationWindow = .quarterHour
        #expect(setup.model.mapStations.isEmpty)
        setup.model.mapStationWindow = .hour
        #expect(setup.names == ["N1CALL"])
        setup.time.advance(by: 2 * 24 * 60 * Self.minute)
        #expect(setup.model.mapStations.isEmpty)
        setup.model.mapStationWindow = .all
        #expect(setup.names == ["N1CALL"])
    }

    @Test("without APRS or with the layer off, there are no stations")
    func off() async throws {
        let setup = try Setup()
        await setup.receive(Self.first)
        setup.model.mapLayers.remove(.stations)
        #expect(setup.model.mapStations.isEmpty)
        setup.model.mapLayers.insert(.stations)
        setup.model.isAPRSEnabled = false
        #expect(setup.model.mapStations.isEmpty)
    }

    @Test("the stored packets bring the stations that memory no longer holds, while the map is shown")
    func fromHistory() async throws {
        let setup = try Setup(listLimit: 1)
        await setup.receive(Self.first)
        await setup.receive(Self.second)
        #expect(await eventually { (try? await setup.history.count()) == 2 })
        await setup.receive(Self.status)
        #expect(setup.names.isEmpty || setup.names.count < 2)
        setup.model.isMapVisible = true
        #expect(await eventually { Set(setup.names) == ["N1CALL", "N2CALL"] })
        setup.model.mapStationWindow = .quarterHour
        setup.time.advance(by: 20 * Self.minute)
        setup.model.mapStationWindow = .hour
        #expect(await eventually { Set(setup.names) == ["N1CALL", "N2CALL"] })
        // Two days on, only all that was heard brings them back from the store.
        setup.time.advance(by: 2 * 24 * 60 * Self.minute)
        setup.model.mapStationWindow = .day
        #expect(await eventually { setup.model.storedMapStations.isEmpty })
        setup.model.mapStationWindow = .all
        #expect(await eventually { Set(setup.names) == ["N1CALL", "N2CALL"] })
    }

    @Test("with our position, the nearest station comes first, with its distance")
    func byDistance() async throws {
        let setup = try Setup(location: FakeLocation())
        await setup.receive(Self.second)
        await setup.receive(Self.first)
        #expect(setup.names == ["N1CALL", "N2CALL"])
        setup.model.isMapVisible = true
        #expect(await eventually { setup.model.ownPosition != nil })
        #expect(setup.names == ["N1CALL", "N2CALL"])
        #expect(setup.model.mapStations.allSatisfy { $0.distanceMeters != nil })
        await setup.receive(Self.second)
        #expect(setup.names == ["N1CALL", "N2CALL"])
        // Our own beacon has no distance, and comes last.
        await setup.receive(Self.own)
        #expect(setup.names == ["N1CALL", "N2CALL", "N0CALL"])
    }

    @Test("without our position, the station heard last comes first")
    func byTime() async throws {
        let setup = try Setup()
        await setup.receive(Self.first)
        await setup.receive(Self.second)
        #expect(setup.names == ["N2CALL", "N1CALL"])
    }

    @Test("a station leads to its packets on the packets page")
    func packets() async throws {
        let setup = try Setup()
        await setup.receive(Self.first)
        await setup.receive(Self.object)
        let object = try #require(setup.model.mapStations.first { $0.id == "OBJECT" })
        setup.model.aprsPage = .chats
        await setup.model.showPackets(of: object)
        #expect(setup.model.aprsFilter(in: .main).callsign == "N1CALL")
        #expect(setup.model.aprsPage == .packets)
        #expect(setup.model.packetsRequestCount == 1)
        setup.model.isAPRSEnabled = false
        await setup.model.showPackets(of: object)
        #expect(setup.model.packetsRequestCount == 1)
    }

    @Test("the frame of the map holds the stations as well")
    func frame() async throws {
        let setup = try Setup()
        await setup.receive(Self.first)
        let station = try #require(setup.model.mapStations.first)
        #expect(setup.model.mapFrame == MapFrame(around: [station.point]))
    }

    @Test("the demo has stations on the map")
    func demo() async throws {
        let setup = try Setup()
        await setup.model.loadDemoContent()
        #expect(setup.names.contains("N1CALL"))
    }
}
