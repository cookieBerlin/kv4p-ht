#if os(iOS)
    import AVFoundation

    /// Configures the shared `AVAudioSession` for play and record and forwards its notifications. All logic lives in
    /// `RadioViewModel`; this file is excluded from coverage (ADR-0011).
    public final class AVAudioSessionAdapter: AudioSession, @unchecked Sendable {
        public let events: AsyncStream<AudioSessionEvent>
        private let observers: [any NSObjectProtocol]

        public init() {
            let (events, continuation) = AsyncStream.makeStream(of: AudioSessionEvent.self)
            self.events = events
            let center = NotificationCenter.default
            let session = AVAudioSession.sharedInstance()
            observers = [
                center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: nil) {
                    let info = $0.userInfo ?? [:]
                    switch (info[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(
                        AVAudioSession.InterruptionType.init
                    ) {
                    case .began:
                        continuation.yield(.interruptionBegan)
                    case .ended:
                        let options = AVAudioSession.InterruptionOptions(
                            rawValue: info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                        )
                        continuation.yield(.interruptionEnded(shouldResume: options.contains(.shouldResume)))
                    default:
                        break
                    }
                },
                center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: nil) {
                    let reason = ($0.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                        .flatMap(AVAudioSession.RouteChangeReason.init)
                    if reason == .oldDeviceUnavailable { continuation.yield(.deviceUnavailable) }
                },
                center.addObserver(
                    forName: AVAudioSession.mediaServicesWereResetNotification,
                    object: session,
                    queue: nil
                ) { _ in
                    continuation.yield(.mediaServicesReset)
                },
            ]
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }

        public func activate() throws {
            let session = AVAudioSession.sharedInstance()
            // The speaker instead of the earpiece; Bluetooth headsets for both directions; other apps keep playing.
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP, .mixWithOthers]
            )
            try session.setActive(true)
        }

        public func deactivate() {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
#endif
