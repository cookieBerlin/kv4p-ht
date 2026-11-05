#if canImport(CoreLocation)
    import CoreLocation

    /// The device location from CoreLocation; asks for "while using" permission. Forwarding only, excluded from
    /// coverage (ADR-0011).
    public final class CoreLocationProvider: LocationProvider {
        private static let timeout = Duration.seconds(30)

        private let diagnostics: DiagnosticLog?

        public init(diagnostics: DiagnosticLog? = nil) {
            self.diagnostics = diagnostics
        }

        public func currentLocation() async -> GeoPoint? {
            let diagnostics = diagnostics
            return await withTaskGroup(of: GeoPoint?.self) { group in
                group.addTask { await Self.firstLocation(diagnostics) }
                group.addTask {
                    try? await Task.sleep(for: Self.timeout)
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                if first == nil {
                    diagnostics?.log(.info, .location, "No location within the time")
                }
                return first
            }
        }

        private static func firstLocation(_ diagnostics: DiagnosticLog?) async -> GeoPoint? {
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
                        diagnostics?.log(.info, .location, "Location access is denied or restricted")
                        return nil
                    }
                }
            } catch {
                diagnostics?.log(.error, .location, "Location updates: \(DiagnosticLog.describe(error))")
                return nil
            }
            return nil
        }
    }
#endif
