import Foundation
import KV4PAPRS
import KV4PPersistence

/// How far back the map shows the APRS stations heard (ADR-0068).
public enum MapStationWindow: String, CaseIterable, Codable, Sendable {
    case quarterHour, hour, sixHours, day, all

    public var title: String {
        switch self {
        case .quarterHour: "15 min"
        case .hour: "1 h"
        case .sixHours: "6 h"
        case .day: "24 h"
        case .all: "All"
        }
    }

    /// `nil` for all that was heard.
    public var milliseconds: Int64? {
        let minute: Int64 = 60_000
        switch self {
        case .quarterHour: return 15 * minute
        case .hour: return 60 * minute
        case .sixHours: return 6 * 60 * minute
        case .day: return 24 * 60 * minute
        case .all: return nil
        }
    }
}

/// An APRS station or object on the map, at its last position.
public struct MapStation: Identifiable, Equatable, Sendable {
    /// The callsign, or the name of an object.
    public let id: String
    /// Its last packet with a position.
    public let event: APRSEvent
    public let point: GeoPoint
    /// `nil` while our own position is unknown, and for our own station.
    public let distanceMeters: Double?
    public let direction: CompassPoint?

    /// What its marker says.
    public var name: String { event.mapLabel }
}

extension APRSEvent {
    /// Who a position belongs to: an object to its name, anything else to its sender.
    var stationKey: String {
        guard kind == .object, let objectName else { return fromCallsign }
        return objectName.trimmingCharacters(in: .whitespaces)
    }
}

extension RadioViewModel {
    /// The kinds of packet that can hold a position.
    static let positionKinds: Set<APRSEvent.Kind> = [.position, .object, .weather]

    /// How many stored packets the map reads at most, so that "all" stays quick.
    static let mapHistoryLimit = 5_000

    /// The APRS stations heard within the window, each at its last position; the nearest first once our own
    /// position is known, otherwise the one heard last.
    public var mapStations: [MapStation] {
        guard isAPRSEnabled, mapLayers.contains(.stations) else { return [] }
        let since = mapStationWindow.milliseconds.map { now() - $0 } ?? .min
        let heard = (Array(storedMapStations.values) + aprs.events).filter {
            Self.positionKinds.contains($0.kind) && $0.lastSeenMs >= since
        }
        let newest = Dictionary(grouping: heard, by: \.stationKey).compactMapValues {
            $0.max { $0.lastSeenMs < $1.lastSeenMs }
        }
        let stations = newest.compactMap { key, event -> MapStation? in
            guard !event.isRemovedObject, let position = position(of: event) else { return nil }
            return MapStation(
                id: key,
                event: event,
                point: position.point,
                distanceMeters: position.distanceMeters,
                direction: position.direction
            )
        }
        guard ownPosition != nil else {
            return stations.sorted { ($0.event.lastSeenMs, $1.id) > ($1.event.lastSeenMs, $0.id) }
        }
        // Our own station has no distance, and comes last.
        return stations.map { (distance: $0.distanceMeters ?? .infinity, station: $0) }
            .sorted { ($0.distance, $0.station.id) < ($1.distance, $1.station.id) }
            .map(\.station)
    }

    /// Reads the last position of each station from the store, while the map shows them.
    func refreshMapStations() {
        guard isMapVisible, isAPRSEnabled, mapLayers.contains(.stations), let aprsHistory else { return }
        let since = mapStationWindow.milliseconds.map { now() - $0 } ?? .min
        let filter = APRSHistoryFilter(kinds: Set(Self.positionKinds.map(\.rawValue)))
        let pageSize = aprsListLimit
        Task { [weak self] in
            var found: [String: APRSEvent] = [:]
            var before: Int64?
            var read = 0
            while read < Self.mapHistoryLimit,
                let page = try? await aprsHistory.page(before: before, limit: pageSize, filter: filter)
            {
                read += page.count
                for event in page.compactMap(Self.event) where event.lastSeenMs >= since {
                    if found[event.stationKey] == nil { found[event.stationKey] = event }
                }
                guard page.count == pageSize, let last = page.last, last.lastSeenMs >= since else { break }
                // The page is newest first and includes `before`, so the next one starts just below.
                before = last.lastSeenMs - 1
            }
            self?.storedMapStations = found
        }
    }

    /// The packets of a station on the packets page, from the main list's search.
    public func showPackets(of station: MapStation) async {
        guard isAPRSEnabled else { return }
        var filter = aprsFilter(in: .main)
        filter.callsign = station.event.fromCallsign
        await setAPRSFilter(filter, in: .main)
        aprsPage = .packets
        packetsRequestCount += 1
    }
}
