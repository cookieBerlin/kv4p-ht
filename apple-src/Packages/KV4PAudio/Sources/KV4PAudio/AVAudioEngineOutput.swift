#if canImport(AVFoundation)
    import AVFoundation
    import KV4PDiagnostics
    import KV4PProtocol
    import Synchronization

    /// Pulls `RXAudioPlayer` samples from an `AVAudioSourceNode`; the engine resamples to the output device.
    /// All logic lives in `RXAudioPlayer`; this file is excluded from coverage (ADR-0011).
    public final class AVAudioEngineOutput: AudioOutput {
        private struct Session: @unchecked Sendable {
            let engine: AVAudioEngine
            let observer: any NSObjectProtocol
        }

        private struct UnsupportedFormat: Error {}

        private let session = Mutex<Session?>(nil)

        private let diagnostics: DiagnosticLog?

        public init(diagnostics: DiagnosticLog? = nil) {
            self.diagnostics = diagnostics
        }

        deinit {
            stop()
        }

        public func start(_ player: RXAudioPlayer) throws {
            stop()
            let engine = AVAudioEngine()
            guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(KV4P.audioSampleRate), channels: 1)
            else { throw UnsupportedFormat() }
            let source = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
                for buffer in UnsafeMutableAudioBufferListPointer(audioBufferList) {
                    let samples = buffer.mData?.assumingMemoryBound(to: Float.self)
                    player.render(into: UnsafeMutableBufferPointer(start: samples, count: Int(frameCount)))
                }
                return noErr
            }
            engine.attach(source)
            try engine.connectNode(source, to: engine.mainMixerNode, format: format)
            // The engine stops when the output device changes (e.g. headphones); it continues on the new one.
            let observer = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange,
                object: engine,
                queue: nil
            ) { [engine, diagnostics] _ in
                do {
                    try engine.start()
                    diagnostics?.log(.info, .audio, "other audio: output restarted after a configuration change")
                } catch {
                    diagnostics?.log(.error, .audio, "other audio: output did not restart: \(error)")
                }
            }
            try engine.start()
            session.withLock { $0 = Session(engine: engine, observer: observer) }
        }

        public func stop() {
            guard let stopped = session.withLock({ $0.take() }) else { return }
            NotificationCenter.default.removeObserver(stopped.observer)
            stopped.engine.stop()
        }
    }
#endif
