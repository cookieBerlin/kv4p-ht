#if os(macOS)
    import Darwin
    import Foundation
    import Synchronization

    /// Forwards between a POSIX serial device and `SerialTransport` (ADR-0018). Excluded from coverage (ADR-0011) and
    /// verified with the hardware checklist.
    public final class POSIXSerialPort: SerialPort {
        public let path: String
        private let source = Mutex<(any DispatchSourceRead)?>(nil)
        private let descriptor = Mutex<Int32>(-1)
        private let queue = DispatchQueue(label: "kv4p.serial")

        public init(path: String) {
            self.path = path
        }

        /// The USB serial devices currently present.
        public static func devices() -> [String] {
            SerialDevices.candidates(in: (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? [])
        }

        public func open() throws(TransportError) -> AsyncStream<[UInt8]> {
            let fd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
            guard fd >= 0 else { throw .portUnavailable(path: path, errno: errno) }
            var options = termios()
            tcgetattr(fd, &options)
            cfmakeraw(&options)
            cfsetspeed(&options, speed_t(B115200))
            options.c_cflag |= tcflag_t(CLOCAL | CREAD)
            guard tcsetattr(fd, TCSANOW, &options) == 0, fcntl(fd, F_SETFL, 0) == 0 else {
                let error = errno
                Darwin.close(fd)
                throw .portUnavailable(path: path, errno: error)
            }
            descriptor.withLock { $0 = fd }
            let (stream, continuation) = AsyncStream.makeStream(of: [UInt8].self)
            let reader = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            reader.setEventHandler {
                var buffer = [UInt8](repeating: 0, count: 4096)
                let count = read(fd, &buffer, buffer.count)
                guard count > 0 else { return reader.cancel() }
                continuation.yield(Array(buffer.prefix(count)))
            }
            reader.setCancelHandler {
                continuation.finish()
                Darwin.close(fd)
            }
            source.withLock { $0 = reader }
            reader.resume()
            return stream
        }

        public func setModemLines(dtr: Bool, rts: Bool) throws(TransportError) {
            let fd = descriptor.withLock { $0 }
            var lines: Int32 = 0
            guard ioctl(fd, TIOCMGET, &lines) == 0 else { throw .ioFailed(errno: errno) }
            lines = (lines & ~(TIOCM_DTR | TIOCM_RTS)) | (dtr ? TIOCM_DTR : 0) | (rts ? TIOCM_RTS : 0)
            guard ioctl(fd, TIOCMSET, &lines) == 0 else { throw .ioFailed(errno: errno) }
        }

        public func write(_ bytes: [UInt8]) throws(TransportError) {
            let fd = descriptor.withLock { $0 }
            var offset = 0
            while offset < bytes.count {
                let written = bytes[offset...].withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
                guard written > 0 else { throw .ioFailed(errno: errno) }
                offset += written
            }
        }

        public func close() {
            descriptor.withLock { $0 = -1 }
            source.withLock { source in
                source?.cancel()
                source = nil
            }
        }
    }
#endif
