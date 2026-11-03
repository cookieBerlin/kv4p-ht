#if canImport(AVFoundation)
    import AVFoundation
    import KV4PProtocol
    import OSLog
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

        private static let log = Logger(subsystem: "kv4p-ht", category: "microphone")

        private let session = Mutex<Session?>(nil)
        /// A new engine takes long to start, which PTT would feel. It is kept between transmissions.
        private let prepared = Mutex<PreparedEngine?>(nil)

        public init() {}

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
            let begin = ContinuousClock.now
            stop()
            if AVAudioApplication.shared.recordPermission != .granted {
                guard await AVAudioApplication.requestRecordPermission() else { throw Unavailable() }
            }
            let engine = prepared.withLock { $0.take() }?.engine ?? AVAudioEngine()
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
            let isFirstBuffer = Mutex(true)
            input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, _ in
                if isFirstBuffer.withLock({ $0 }) {
                    isFirstBuffer.withLock { $0 = false }
                    Self.log.info(
                        "first samples after \(String(describing: ContinuousClock.now - begin), privacy: .public)"
                    )
                }
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
                throw Unavailable()
            }
            session.withLock { $0 = Session(engine: engine, continuation: continuation) }
            Self.log.info("started in \(String(describing: ContinuousClock.now - begin), privacy: .public)")
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
