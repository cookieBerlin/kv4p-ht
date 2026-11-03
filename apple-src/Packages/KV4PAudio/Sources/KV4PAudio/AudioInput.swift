/// Captures the microphone; implemented by the OS adapter (`AVAudioEngineInput`).
public protocol AudioInput: Sendable {
    /// Gets ready for a quick `start()`, without capturing or asking for access.
    func prepare()
    /// Asks for microphone access if needed, then delivers samples at `KV4P.audioSampleRate`, mono, until `stop()`.
    func start() async throws -> AsyncStream<[Int16]>
    func stop()
}
