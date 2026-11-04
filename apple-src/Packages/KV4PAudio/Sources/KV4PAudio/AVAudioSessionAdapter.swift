#if os(iOS)
    import AVFoundation

    /// Configures the shared `AVAudioSession` for play and record and forwards its notifications. All logic lives in
    /// `RadioViewModel`; this file is excluded from coverage (ADR-0011).
    public final class AVAudioSessionAdapter: AudioSession, @unchecked Sendable {
        public let events: AsyncStream<AudioSessionEvent>
        private let observers: [any NSObjectProtocol]
        private let queue = DispatchQueue(label: "kv4p.audio-session", qos: .userInitiated)

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
            // Other apps keep playing.
            try activate(otherAudio: .mixWithOthers)
        }

        private func activate(otherAudio: AVAudioSession.CategoryOptions) throws {
            let session = AVAudioSession.sharedInstance()
            // The speaker instead of the earpiece; Bluetooth headsets for both directions.
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: otherAudio.union([.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP])
            )
            // iOS mutes haptics during a recording session by default, and PTT confirms a press with one.
            try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
            try session.setActive(true)
        }

        /// Session calls block for up to a second, too long for the main thread.
        private func onSessionQueue<T: Sendable>(_ call: @escaping @Sendable () throws -> T) async throws -> T {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { continuation.resume(with: Result(catching: call)) }
            }
        }

        public var isOtherAudioPlaying: Bool {
            AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint
        }

        public func lowerOtherAudio(_ mode: OtherAudioMode) async throws {
            let options: AVAudioSession.CategoryOptions =
                mode == .pausePodcasts ? [.interruptSpokenAudioAndMixWithOthers, .duckOthers] : .duckOthers
            try await onSessionQueue { [self] in
                // Locked, iOS refuses a new category for an active session (`cannotInterruptOthers`).
                try AVAudioSession.sharedInstance().setActive(false)
                try activate(otherAudio: options)
            }
        }

        public func releaseOtherAudio() async {
            try? await onSessionQueue {
                try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }

        public func mixWithOtherAudio() async throws {
            try await onSessionQueue { [self] in try activate(otherAudio: .mixWithOthers) }
        }

        public func deactivate() {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
#endif
