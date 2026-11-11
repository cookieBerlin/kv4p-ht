import Foundation
import KV4PPersistence

/// A layer of the map, one for each kind of memory, switched on and off on its own (ADR-0068).
public enum MapLayer: String, CaseIterable, Codable, Sendable {
    case repeaters, frequencies, beacons

    public init(_ kind: MemoryKind) {
        switch kind {
        case .repeater: self = .repeaters
        case .frequency: self = .frequencies
        case .beacon: self = .beacons
        }
    }

    public var title: String {
        switch self {
        case .repeaters: "Repeaters"
        case .frequencies: "Frequencies"
        case .beacons: "Beacons"
        }
    }
}

/// A memory on the map, and how far from here it is.
public struct MapPoint: Identifiable, Equatable, Sendable {
    public let memory: ChannelMemory
    public let point: GeoPoint
    /// `nil` while our own position is unknown.
    public let distanceMeters: Double?
    public let direction: CompassPoint?
    /// The radio is ready and receives it, as in the list.
    public let isTunable: Bool

    public var id: Int32 { memory.id }
}

/// The part of the map shown first: all points with a margin, and a few kilometres around a single one.
public struct MapFrame: Equatable, Sendable {
    /// In degrees, about 5 km from north to south.
    public static let smallestDelta = 0.05
    /// The part of the span left free beyond the outermost points on each side, so their markers are whole.
    public static let margin = 0.25

    public let center: GeoPoint
    public let latitudeDelta: Double
    public let longitudeDelta: Double

    /// `nil` without any place, so the map keeps its own. A frame across the date line goes round the other way.
    public init?(around points: [GeoPoint]) {
        guard let first = points.first else { return nil }
        var (south, north, west, east) = (first.latitude, first.latitude, first.longitude, first.longitude)
        for point in points {
            south = min(south, point.latitude)
            north = max(north, point.latitude)
            west = min(west, point.longitude)
            east = max(east, point.longitude)
        }
        center = GeoPoint(latitude: (south + north) / 2, longitude: (west + east) / 2)
        latitudeDelta = Self.delta(north - south)
        longitudeDelta = Self.delta(east - west)
    }

    private static func delta(_ span: Double) -> Double {
        max(smallestDelta, span * (1 + 2 * margin))
    }
}

extension ChannelMemory {
    /// Where it is, with both coordinates known; the form only keeps real numbers, but a synced one may not.
    public var position: GeoPoint? {
        guard let latitude, let longitude, latitude.isFinite, longitude.isFinite else { return nil }
        return GeoPoint(latitude: latitude, longitude: longitude)
    }
}

extension RadioViewModel {
    /// The memories with a position on the layers that are on, from all groups; the nearest first once our own
    /// position is known, otherwise in the order of the list.
    public var mapPoints: [MapPoint] {
        let points = memories.compactMap { memory -> MapPoint? in
            guard mapLayers.contains(MapLayer(memory.kind)), let point = memory.position else { return nil }
            let (distance, direction) = point.seen(from: ownPosition)
            return MapPoint(
                memory: memory,
                point: point,
                distanceMeters: distance,
                direction: direction,
                isTunable: isReady && isReceivable(memory)
            )
        }
        guard let own = ownPosition else { return points }
        // The order of the list among points as far away.
        return points.enumerated()
            .map { (distance: own.distance(to: $0.element.point), offset: $0.offset, point: $0.element) }
            .sorted { ($0.distance, $0.offset) < ($1.distance, $1.offset) }
            .map(\.point)
    }

    /// What the map shows first: its points and our own position.
    public var mapFrame: MapFrame? {
        MapFrame(around: mapPoints.map(\.point) + [ownPosition].compactMap(\.self))
    }
}
