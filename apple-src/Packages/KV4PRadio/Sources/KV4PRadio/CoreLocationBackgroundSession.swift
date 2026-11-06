#if os(iOS)
    import CoreLocation

    /// Keeps the location available in the background with *when in use* access, and shows the system's indicator: forwards
    /// only (ADR-0056).
    public final class CoreLocationBackgroundSession: BackgroundLocationKeeping {
        private var session: CLBackgroundActivitySession?

        public init() {}

        public func start() {
            session = CLBackgroundActivitySession()
        }

        public func stop() {
            session?.invalidate()
            session = nil
        }
    }
#endif
