import Foundation
import KV4PTestSupport
import Synchronization
import Testing

@testable import KV4PAPRS
@testable import KV4PRadio

/// Where a station of the APRS list is, and how far from here (ADR-0053).
@MainActor
@Suite("Station position")
struct StationPositionTests {
    private final class CountingLocation: LocationProvider {
        private let reads = Mutex(0)
        var count: Int { reads.withLock { $0 } }
        let point: GeoPoint?

        init(_ point: GeoPoint? = GeoPoint(latitude: 49, longitude: -72)) {
            self.point = point
        }

        func currentLocation() async -> GeoPoint? {
            reads.withLock { $0 += 1 }
            return point
        }
    }

    private static let degreeOnEarth = 111_195.0
    private static let position = "N1CALL>APRS,TCPIP*:=4903.50N/07201.75W-Test"

    private static func event(latitude: Double, longitude: Double, from: String = "N1CALL") -> APRSEvent {
        var event = APRSEvent(firstSeenMs: 0, lastSeenMs: 0, fromCallsign: from)
        event.kind = .position
        event.latitude = latitude
        event.longitude = longitude
        return event
    }

    private static func model(
        permissions: FakePermissions = FakePermissions(),
        location: (any LocationProvider)? = CountingLocation(),
        internet: FakeLink? = nil,
        time: TestTime = TestTime()
    ) -> RadioViewModel {
        RadioViewModel(
            makeController: { _, _ in RadioController(transport: ScriptedTransport()) },
            serialDevices: { [] },
            location: location,
            internet: internet,
            permissions: permissions,
            now: { time.ms }
        )
    }

    @Test(
        "a degree is the same distance along a meridian, along the equator and over the date line",
        arguments: [
            (GeoPoint(latitude: 0, longitude: 0), GeoPoint(latitude: 1, longitude: 0)),
            (GeoPoint(latitude: 0, longitude: 0), GeoPoint(latitude: 0, longitude: 1)),
            (GeoPoint(latitude: 0, longitude: 179.5), GeoPoint(latitude: 0, longitude: -179.5)),
            (GeoPoint(latitude: 89, longitude: 0), GeoPoint(latitude: 90, longitude: 120)),
        ]
    )
    func distance(from: GeoPoint, to: GeoPoint) {
        #expect(abs(from.distance(to: to) - Self.degreeOnEarth) < 10)
    }

    @Test("the same place is no distance away")
    func samePlace() {
        let point = GeoPoint(latitude: 49, longitude: -72)
        #expect(point.distance(to: point) == 0)
    }

    @Test(
        "the direction is one of eight",
        arguments: [
            (1.0, 0.0, CompassPoint.north), (1, 1, .northEast), (0, 1, .east), (-1, 1, .southEast),
            (-1, 0, .south), (-1, -1, .southWest), (0, -1, .west), (1, -1, .northWest),
        ]
    )
    func direction(latitude: Double, longitude: Double, point: CompassPoint) {
        let here = GeoPoint(latitude: 0, longitude: 0)
        #expect(here.direction(to: GeoPoint(latitude: latitude, longitude: longitude)) == point)
    }

    @Test("over the date line the short way counts")
    func directionOverDateLine() {
        let here = GeoPoint(latitude: 0, longitude: 179.5)
        #expect(here.direction(to: GeoPoint(latitude: 0, longitude: -179.5)) == .east)
    }

    @Test("the directions have short labels")
    func labels() {
        #expect(CompassPoint.allCases.map(\.label) == ["N", "NE", "E", "SE", "S", "SW", "W", "NW"])
    }

    @Test("a packet without coordinates has no position")
    func none() {
        let model = Self.model()
        let event = APRSEvent(firstSeenMs: 0, lastSeenMs: 0, fromCallsign: "N1CALL")
        #expect(model.position(of: event) == nil)
    }

    @Test("any packet with coordinates has a position, with a link to the map named after it")
    func link() throws {
        let model = Self.model()
        var event = Self.event(latitude: 49.05, longitude: -72.025)
        let position = try #require(model.position(of: event))
        #expect(position.point == GeoPoint(latitude: 49.05, longitude: -72.025))
        let station = try #require(position.mapURL?.absoluteString)
        #expect(station.hasPrefix("https://maps.apple.com/"))
        #expect(station.contains("ll=49.05,-72.025"))
        #expect(station.contains("q=N1CALL"))
        event.kind = .object
        event.objectName = "TEST OBJ"
        let object = try #require(model.position(of: event)?.mapURL?.absoluteString)
        #expect(object.contains("q=TEST%20OBJ"))
    }

    @Test("a coordinate of 0 alone is a position")
    func onEquator() {
        #expect(Self.model().position(of: Self.event(latitude: 0, longitude: 10)) != nil)
        #expect(Self.model().position(of: Self.event(latitude: 10, longitude: 0)) != nil)
    }

    @Test("without a position of ours there is no distance")
    func noOwnPosition() {
        let position = Self.model().position(of: Self.event(latitude: 49, longitude: -72))
        #expect(position?.distanceMeters == nil)
        #expect(position?.direction == nil)
    }

    @Test("with a position of ours there is a distance and a direction")
    func withOwnPosition() async {
        let model = Self.model()
        model.isAPRSVisible = true
        #expect(await KV4PTestSupport.eventually { model.ownPosition != nil })
        let position = model.position(of: Self.event(latitude: 50, longitude: -72))
        #expect(abs((position?.distanceMeters ?? 0) - Self.degreeOnEarth) < 10)
        #expect(position?.direction == .north)
    }

    @Test("very near, a direction says nothing")
    func nearby() async {
        let model = Self.model()
        model.isAPRSVisible = true
        #expect(await KV4PTestSupport.eventually { model.ownPosition != nil })
        let position = model.position(of: Self.event(latitude: 49.0005, longitude: -72))
        #expect(position?.distanceMeters != nil)
        #expect(position?.direction == nil)
    }

    @Test("a packet of our own has no distance")
    func own() async {
        let model = Self.model()
        model.callsign = "N0CALL"
        model.isAPRSVisible = true
        #expect(await KV4PTestSupport.eventually { model.ownPosition != nil })
        let position = model.position(of: Self.event(latitude: 50, longitude: -72, from: "N0CALL"))
        #expect(position != nil)
        #expect(position?.distanceMeters == nil)
    }

    @Test("the position is only read while the list is shown and access is granted")
    func readsOnlyWhenNeeded() async {
        let hidden = CountingLocation()
        _ = Self.model(location: hidden)
        await Task.yield()
        #expect(hidden.count == 0)

        let undecided = CountingLocation()
        let model = Self.model(permissions: FakePermissions([.location: .notDetermined]), location: undecided)
        model.isAPRSVisible = true
        await Task.yield()
        #expect(undecided.count == 0)

        let noProvider = Self.model(location: nil)
        noProvider.isAPRSVisible = true
        #expect(noProvider.ownPosition == nil)
    }

    @Test("it is read at most once a minute, again when a new position arrives")
    func onceAMinute() async {
        let location = CountingLocation()
        let link = FakeLink()
        let time = TestTime()
        let model = Self.model(location: location, internet: link, time: time)
        model.isAPRSVisible = true
        #expect(await KV4PTestSupport.eventually { location.count == 1 })
        link.receive.yield(Self.position)
        #expect(await KV4PTestSupport.eventually { !model.aprsEvents.isEmpty })
        #expect(location.count == 1)
        time.advance(by: 60_000)
        link.receive.yield(Self.position + "2")
        #expect(await KV4PTestSupport.eventually { location.count == 2 })
    }

    @Test("a packet without a position and a hidden list read nothing")
    func noReason() async {
        let location = CountingLocation()
        let link = FakeLink()
        let time = TestTime()
        let model = Self.model(location: location, internet: link, time: time)
        link.receive.yield(Self.position)
        #expect(await KV4PTestSupport.eventually { !model.aprsEvents.isEmpty })
        #expect(location.count == 0)
        model.isAPRSVisible = true
        #expect(await KV4PTestSupport.eventually { location.count == 1 })
        model.isAPRSVisible = false
        time.advance(by: 60_000)
        link.receive.yield(Self.position + "2")
        #expect(await KV4PTestSupport.eventually { model.aprsEvents.count == 2 })
        #expect(location.count == 1)
    }

    @Test("an unknown position leaves the last one")
    func unknown() async {
        let location = CountingLocation(nil)
        let model = Self.model(location: location)
        model.isAPRSVisible = true
        #expect(await KV4PTestSupport.eventually { location.count == 1 })
        await Task.yield()
        #expect(model.ownPosition == nil)
    }

    @Test("the offer to show distances stands until the question is answered")
    func offer() async {
        let permissions = FakePermissions([.location: .notDetermined])
        let model = Self.model(permissions: permissions)
        #expect(model.offersDistances)
        model.askForDistances()
        #expect(permissions.requested == [.location])
        permissions.set(.location, .granted)
        #expect(await KV4PTestSupport.eventually { !model.offersDistances })
    }

    @Test("access granted while the list is shown brings the distances")
    func grantedLater() async {
        let permissions = FakePermissions([.location: .notDetermined])
        let model = Self.model(permissions: permissions)
        model.isAPRSVisible = true
        #expect(model.ownPosition == nil)
        permissions.set(.location, .granted)
        #expect(await KV4PTestSupport.eventually { model.ownPosition != nil })
    }

    @Test("access denied ends the distances and makes no offer")
    func denied() async {
        let permissions = FakePermissions()
        let model = Self.model(permissions: permissions)
        model.isAPRSVisible = true
        #expect(await KV4PTestSupport.eventually { model.ownPosition != nil })
        permissions.set(.location, .denied)
        #expect(await KV4PTestSupport.eventually { model.ownPosition == nil })
        #expect(!model.offersDistances)
    }

    @Test("without a location provider or permissions there is no offer")
    func noOffer() {
        #expect(!Self.model(permissions: FakePermissions([.location: .notDetermined]), location: nil).offersDistances)
        #expect(!Self.model(permissions: FakePermissions([.location: .granted])).offersDistances)
    }

    @Test("a position read for the beacon or the feed serves the distances as well")
    func reused() async {
        let setup = RadioViewModelInternetTests.Setup()
        setup.location.set(GeoPoint(latitude: 49, longitude: -72))
        setup.model.callsign = "N0CALL"
        setup.model.isInternetFeedEnabled = true
        #expect(await KV4PTestSupport.eventually { setup.model.ownPosition != nil })
    }
}
