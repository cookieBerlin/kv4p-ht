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
    case keepPlaying, lower, pausePodcasts, muteAll

    /// What a platform with an audio session can do: iPhone and iPad.
    public static let withAudioSession: [OtherAudioMode] = [.keepPlaying, .lower, .pausePodcasts]
    /// What a platform without one can do: the Mac (ADR-0044).
    public static let withoutAudioSession: [OtherAudioMode] = [.keepPlaying, .muteAll]

    public var label: String {
        switch self {
        case .keepPlaying: "Keep playing"
        case .lower: "Lower all"
        case .pausePodcasts: "Pause podcasts, lower music"
        case .muteAll: "Mute other apps"
        }
    }

    public var changesOtherAudio: Bool { self != .keepPlaying }

    /// What the user should know before choosing this mode.
    public var warning: String? {
        guard self == .keepPlaying else { return nil }
        return "Other apps also keep playing while you transmit. The microphone can pick them up and send them on air."
    }
}

/// Makes other apps get out of the way of the radio (ADR-0043, ADR-0044).
public protocol OtherAudioSwitching: Sendable {
    /// Another app plays audio that the radio should not compete with.
    var isOtherAudioPlaying: Bool { get }
    /// Makes other apps do what `mode` says, for a signal. With an audio session, the caller stops the audio first.
    func lowerOtherAudio(_ mode: OtherAudioMode) async throws
    /// Silences all other apps with the microphone available, for a transmission.
    func silenceOtherAudio() async throws
    /// Lets other apps go on. With an audio session, the caller stops the audio first.
    func releaseOtherAudio() async
    /// Plays next to other apps again, after `releaseOtherAudio()`.
    func mixWithOtherAudio() async throws
}

/// The audio session of the app; implemented by the OS adapter (`AVAudioSessionAdapter`, iOS only).
public protocol AudioSession: OtherAudioSwitching {
    var events: AsyncStream<AudioSessionEvent> { get }
    /// Configures the session for receiving and transmitting, then activates it.
    func activate() throws
    func deactivate()
}
