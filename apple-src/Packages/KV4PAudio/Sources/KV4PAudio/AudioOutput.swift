/// Plays what an `RXAudioPlayer` renders; implemented by the OS adapter (`AVAudioEngineOutput`).
public protocol AudioOutput: Sendable {
    /// Starts pulling samples from `player` at `KV4P.audioSampleRate`, mono.
    func start(_ player: RXAudioPlayer) throws
    func stop()
}
