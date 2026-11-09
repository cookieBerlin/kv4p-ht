#if canImport(AVFoundation)
    import AVFoundation
    import KV4PDiagnostics
    import KV4PProtocol
    import Synchronization

    /// Captures the default input device and converts it to 16 kHz mono 16-bit samples. All logic lives in
    /// `TXAudioEncoder` and `RadioController`; this file is excluded from coverage (ADR-0011).
    public final class AVAudioEngineInput: AudioInput {
        public struct Unavailable: Error {}

        private struct Session: @unchecked Sendable {
            let engine: AVAudioEngine
            let continuation: AsyncStream<[Int16]>.Continuation
        }

        private struct PreparedEngine: @unchecked Sendable {
            let engine: AVAudioEngine
        }

        private let session = Mutex<Session?>(nil)
        /// A new engine takes long to start, which PTT would feel. It is kept between transmissions.
        private let prepared = Mutex<PreparedEngine?>(nil)

        private let diagnostics: DiagnosticLog?

        public init(diagnostics: DiagnosticLog? = nil) {
            self.diagnostics = diagnostics
        }

        deinit {
            stop()
        }

        public func prepare() {
            let engine = AVAudioEngine()
            _ = engine.inputNode
            engine.prepare()
            prepared.withLock { $0 = PreparedEngine(engine: engine) }
        }

        public func start() async throws -> AsyncStream<[Int16]> {
            stop()
            if AVAudioApplication.shared.recordPermission != .granted {
                guard await AVAudioApplication.requestRecordPermission() else { throw Unavailable() }
            }
            if let engine = prepared.withLock({ $0.take() })?.engine {
                do {
                    return try capture(on: engine)
                } catch {
                    // A prepared engine does not survive every change of the audio session.
                    diagnostics?.log(.error, .audio, "A prepared microphone engine did not start: \(error)")
                }
            }
            do {
                return try capture(on: AVAudioEngine())
            } catch {
                diagnostics?.log(.error, .audio, "The microphone did not start: \(error) \(Self.sessionState)")
                throw error
            }
        }

        /// What the system says about the input when it does not start.
        private static var sessionState: String {
            #if os(iOS)
                let session = AVAudioSession.sharedInstance()
                let inputs = session.currentRoute.inputs.map(\.portType.rawValue).joined(separator: ",")
                let outputs = session.currentRoute.outputs.map(\.portType.rawValue).joined(separator: ",")
                return "category=\(session.category.rawValue) options=\(session.categoryOptions.rawValue) "
                    + "inputAvailable=\(session.isInputAvailable) channels=\(session.inputNumberOfChannels) "
                    + "rate=\(session.sampleRate) inputs=[\(inputs)] outputs=[\(outputs)] "
                    + "other=\(session.isOtherAudioPlaying) hint=\(session.secondaryAudioShouldBeSilencedHint)"
            #else
                return ""
            #endif
        }

        private func capture(on engine: AVAudioEngine) throws -> AsyncStream<[Int16]> {
            let input = engine.inputNode
            let inputFormat = input.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0,
                let format = AVAudioFormat(
                    commonFormat: .pcmFormatInt16,
                    sampleRate: Double(KV4P.audioSampleRate),
                    channels: 1,
                    interleaved: true
                ),
                let converter = AVAudioConverter(from: inputFormat, to: format)
            else { throw Unavailable() }
            converter.downmix = true
            let (samples, continuation) = AsyncStream.makeStream(of: [Int16].self)
            let ratio = format.sampleRate / inputFormat.sampleRate
            // The SDK gives the call that replaces `installTap` no plain Swift name yet.
            try input.__installTap(onBus: 0, bufferSize: 1024, format: inputFormat, error: ()) { buffer, _ in
                let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
                guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
                nonisolated(unsafe) var consumed = false
                _ = converter.convert(to: output, error: nil) { _, status in
                    if consumed {
                        status.pointee = .noDataNow
                        return nil
                    }
                    consumed = true
                    status.pointee = .haveData
                    return buffer
                }
                guard let channel = output.int16ChannelData?[0], output.frameLength > 0 else { return }
                continuation.yield(Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength))))
            }
            engine.prepare()
            do {
                try engine.start()
            } catch {
                input.removeTap(onBus: 0)
                throw error
            }
            session.withLock { $0 = Session(engine: engine, continuation: continuation) }
            return samples
        }

        public func stop() {
            guard let stopped = session.withLock({ $0.take() }) else { return }
            stopped.engine.inputNode.removeTap(onBus: 0)
            stopped.engine.stop()
            stopped.engine.prepare()
            prepared.withLock { $0 = PreparedEngine(engine: stopped.engine) }
            stopped.continuation.finish()
        }
    }
#endif
