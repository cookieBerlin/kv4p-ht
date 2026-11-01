import CCodec2
import Synchronization

/// Codec2 1300, the speech codec of FreeDV 2400B (Android `io.github.dkaukov.codec2.Codec2`): 320 samples at 8 kHz
/// (40 ms) per 7-byte frame. Encoder and decoder keep state between frames; one instance is used by one owner.
public final class Codec2 {
    public static let samplesPerFrame = 320
    public static let bytesPerFrame = 7

    /// The decoder draws random phases from one process-wide generator (`codec2_rand`), so calls of all instances
    /// take turns.
    private static let library = Mutex(())

    private let handle: OpaquePointer

    /// `nil` if Codec2 cannot be created.
    public convenience init?() {
        self.init(mode: CODEC2_MODE_1300)
    }

    /// Only the 1300 mode is compiled in (ADR-0027); other modes are unavailable.
    init?(mode: Int32) {
        guard let handle = codec2_create(mode) else { return nil }
        self.handle = handle
    }

    deinit {
        codec2_destroy(handle)
    }

    /// One frame; `nil` unless `pcm` holds exactly `samplesPerFrame` samples.
    public func encode(_ pcm: some Collection<Int16>) -> [UInt8]? {
        guard pcm.count == Self.samplesPerFrame else { return nil }
        var samples = Array(pcm)
        var frame = [UInt8](repeating: 0, count: Self.bytesPerFrame)
        Self.library.withLock { _ in codec2_encode(handle, &frame, &samples) }
        return frame
    }

    /// `samplesPerFrame` samples; `nil` unless `frame` holds exactly `bytesPerFrame` bytes.
    public func decode(_ frame: some Collection<UInt8>) -> [Int16]? {
        guard frame.count == Self.bytesPerFrame else { return nil }
        var bits = Array(frame)
        var samples = [Int16](repeating: 0, count: Self.samplesPerFrame)
        Self.library.withLock { _ in codec2_decode(handle, &samples, &bits) }
        return samples
    }
}
