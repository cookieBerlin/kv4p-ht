/// A position in degrees.
public struct GeoPoint: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// The device location for position beacons; implemented by the OS adapter (`CoreLocationProvider`).
public protocol LocationProvider: Sendable {
    /// Asks for permission if needed; `nil` when the location is unknown or not allowed.
    func currentLocation() async -> GeoPoint?
}
