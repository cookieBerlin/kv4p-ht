#if os(iOS)
    import AVFoundation
    import os

    /// Configures the shared `AVAudioSession` for play and record and forwards its notifications. All logic lives in
    /// `RadioViewModel`; this file is excluded from coverage (ADR-0011).
    public final class AVAudioSessionAdapter: AudioSession, @unchecked Sendable {
        public let events: AsyncStream<AudioSessionEvent>
        private static let log = Logger(subsystem: "io.github.cookieberlin.kv4pht", category: "session")

        private let observers: [any NSObjectProtocol]
        private let queue = DispatchQueue(label: "kv4p.audio-session", qos: .userInitiated)

        public init() {
            let (events, continuation) = AsyncStream.makeStream(of: AudioSessionEvent.self)
            self.events = events
            let center = NotificationCenter.default
            let session = AVAudioSession.sharedInstance()
            observers = [
                center.addObserver(forName: AVAudioSession.didBecomeInactiveNotification, object: session, queue: nil) {
                    let context =
                        $0.userInfo?[AVAudioSession.deactivationContextKey] as? AVAudioSession.DeactivationContext
                    let other = session.isOtherAudioPlaying
                    Self.log.info(
                        "other audio: INACTIVE system=\(context?.source == .system) other=\(other, privacy: .public)"
                    )
                    // The app also ends the session itself, when it hands the audio back to other apps.
                    if context?.source == .system { continuation.yield(.interruptionBegan) }
                },
                center.addObserver(
                    forName: AVAudioSession.resumptionRecommendationNotification,
                    object: session,
                    queue: nil
                ) {
                    let context = $0.userInfo?[AVAudioSession.resumptionContextKey] as? AVAudioSession.ResumptionContext
                    let shouldResume = context?.recommendation == .shouldResume
                    Self.log.info("other audio: RESUMPTION shouldResume=\(shouldResume, privacy: .public)")
                    continuation.yield(.interruptionEnded(shouldResume: shouldResume))
                },
                center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: nil) {
                    let reason = ($0.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                        .flatMap(AVAudioSession.RouteChangeReason.init)
                    let route = session.currentRoute
                    let inputs = route.inputs.map(\.portType.rawValue).joined(separator: ",")
                    let outputs = route.outputs.map(\.portType.rawValue).joined(separator: ",")
                    Self.log.info(
                        "other audio: route inputs=[\(inputs, privacy: .public)] outputs=[\(outputs, privacy: .public)]"
                    )
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

        public func silenceOtherAudio() async throws {
            try await onSessionQueue { [self] in
                try AVAudioSession.sharedInstance().setActive(false)
                try activate(otherAudio: [])
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
