import Foundation
import KV4PAPRS

/// One of the eight directions of the APRS list.
public enum CompassPoint: CaseIterable, Sendable {
    case north, northEast, east, southEast, south, southWest, west, northWest

    public var label: String {
        switch self {
        case .north: "N"
        case .northEast: "NE"
        case .east: "E"
        case .southEast: "SE"
        case .south: "S"
        case .southWest: "SW"
        case .west: "W"
        case .northWest: "NW"
        }
    }

    /// The nearest point to a bearing in degrees from north, clockwise.
    init(degrees: Double) {
        let index = Int(((degrees + 22.5) / 45).rounded(.down))
        self = Self.allCases[index % Self.allCases.count]
    }
}

extension GeoPoint {
    /// The mean radius, which is close enough for a list: a sphere differs from the Earth by about 0.5 %.
    private static let earthRadiusMeters = 6_371_000.0

    /// The great-circle distance.
    public func distance(to other: GeoPoint) -> Double {
        let (from, to) = (radians(latitude), radians(other.latitude))
        let latitudes = sin((to - from) / 2)
        let longitudes = sin(radians(other.longitude - longitude) / 2)
        let haversine = latitudes * latitudes + cos(from) * cos(to) * longitudes * longitudes
        return 2 * Self.earthRadiusMeters * asin(min(1, haversine.squareRoot()))
    }

    /// The direction of the great circle at the start of the way.
    public func direction(to other: GeoPoint) -> CompassPoint {
        let (from, to) = (radians(latitude), radians(other.latitude))
        let longitudes = radians(other.longitude - longitude)
        let bearing = atan2(sin(longitudes) * cos(to), cos(from) * sin(to) - sin(from) * cos(to) * cos(longitudes))
        return CompassPoint(degrees: (bearing * 180 / .pi + 360).truncatingRemainder(dividingBy: 360))
    }

    private func radians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }
}

/// Where a station of the APRS list is, and how far from here (ADR-0053).
public struct StationPosition: Equatable, Sendable {
    /// Below this, the errors of both positions outweigh the direction.
    private static let shortestDistanceWithDirection = 100.0

    public let point: GeoPoint
    /// Apple Maps with a pin named after the station.
    public let mapURL: URL?
    /// `nil` while our own position is unknown, and for our own packets.
    public let distanceMeters: Double?
    public let direction: CompassPoint?

    /// `nil` for a packet without coordinates. `own` is the position to measure from.
    init?(event: APRSEvent, own: GeoPoint?) {
        guard event.latitude != 0 || event.longitude != 0 else { return nil }
        let point = GeoPoint(latitude: event.latitude, longitude: event.longitude)
        self.point = point
        var map = URLComponents()
        map.scheme = "https"
        map.host = "maps.apple.com"
        map.path = "/"
        map.queryItems = [
            URLQueryItem(name: "ll", value: "\(point.latitude),\(point.longitude)"),
            URLQueryItem(name: "q", value: event.objectName ?? event.fromCallsign),
        ]
        mapURL = map.url
        let distance = own?.distance(to: point)
        distanceMeters = distance
        direction = (distance ?? 0) >= Self.shortestDistanceWithDirection ? own?.direction(to: point) : nil
    }
}
