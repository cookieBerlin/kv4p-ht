#if canImport(CoreLocation)
    import CoreLocation

    /// The device location from CoreLocation; asks for "while using" permission. Forwarding only, excluded from
    /// coverage (ADR-0011).
    public final class CoreLocationProvider: LocationProvider {
        private static let timeout = Duration.seconds(30)

        public init() {}

        public func currentLocation() async -> GeoPoint? {
            await withTaskGroup(of: GeoPoint?.self) { group in
                group.addTask { await Self.firstLocation() }
                group.addTask {
                    try? await Task.sleep(for: Self.timeout)
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }
        }

        private static func firstLocation() async -> GeoPoint? {
            #if os(iOS)
                let session = CLServiceSession(authorization: .whenInUse)
                defer { session.invalidate() }
            #else
                let manager = CLLocationManager()
                manager.requestWhenInUseAuthorization()
                defer { withExtendedLifetime(manager) {} }
            #endif
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    if let location = update.location {
                        return GeoPoint(
                            latitude: location.coordinate.latitude,
                            longitude: location.coordinate.longitude
                        )
                    }
                    if update.authorizationDenied || update.authorizationDeniedGlobally
                        || update.authorizationRestricted
                    {
                        return nil
                    }
                }
            } catch {
                return nil
            }
            return nil
        }
    }
#endif
