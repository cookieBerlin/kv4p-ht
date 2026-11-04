/// What the system tells the app about its audio (iOS `AVAudioSession` notifications).
public enum AudioSessionEvent: Sendable, Equatable {
    /// Another app or a call took the audio; playback and recording have stopped.
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    /// The input or output device in use is gone, e.g. a headset was unplugged or switched off.
    case deviceUnavailable
    /// The audio services restarted; every audio engine must be created again.
    case mediaServicesReset
}

/// What other apps do while the radio receives or the user transmits (ADR-0043).
public enum OtherAudioMode: String, Codable, CaseIterable, Sendable {
    case keepPlaying, lower, pausePodcasts

    public var label: String {
        switch self {
        case .keepPlaying: "Keep playing"
        case .lower: "Lower all"
        case .pausePodcasts: "Pause podcasts, lower music"
        }
    }

    public var changesOtherAudio: Bool { self != .keepPlaying }
}

/// The audio session of the app; implemented by the OS adapter (`AVAudioSessionAdapter`, iOS only).
public protocol AudioSession: Sendable {
    var events: AsyncStream<AudioSessionEvent> { get }
    /// Configures the session for receiving and transmitting, then activates it.
    func activate() throws
    func deactivate()
    /// Another app plays audio that the radio should not compete with.
    var isOtherAudioPlaying: Bool { get }
    /// Deactivates the session, then activates it so that other apps do what `mode` says. The caller stops the audio
    /// first, as the system requires.
    func lowerOtherAudio(_ mode: OtherAudioMode) async throws
    /// Deactivates the session and tells other apps that they can resume. The caller stops the audio first.
    func releaseOtherAudio() async
    /// Activates the session again as in `activate()`, next to what other apps play.
    func mixWithOtherAudio() async throws
}
