#if canImport(AVFoundation)
    import AVFoundation
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

        private let session = Mutex<Session?>(nil)

        public init() {}

        deinit {
            stop()
        }

        public func start() async throws -> AsyncStream<[Int16]> {
            stop()
            guard await AVAudioApplication.requestRecordPermission() else { throw Unavailable() }
            let engine = AVAudioEngine()
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
            input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, _ in
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
            return samples
        }

        public func stop() {
            guard let stopped = session.withLock({ $0.take() }) else { return }
            stopped.engine.inputNode.removeTap(onBus: 0)
            stopped.engine.stop()
            stopped.continuation.finish()
        }
    }
#endif
