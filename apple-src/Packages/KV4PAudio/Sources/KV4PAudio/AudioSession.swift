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

/// The audio session of the app; implemented by the OS adapter (`AVAudioSessionAdapter`, iOS only).
public protocol AudioSession: Sendable {
    var events: AsyncStream<AudioSessionEvent> { get }
    /// Configures the session for receiving and transmitting, then activates it.
    func activate() throws
    func deactivate()
}
