import KV4PTransport

/// `BootloaderPort` over the serial adapter: received bytes are buffered until read, and a read waits at most its
/// timeout, as `UsbSerialPort.read(…, timeout)` does on Android.
public actor SerialBootloaderPort<C: Clock>: BootloaderPort where C.Duration == Duration {
    private let port: any SerialPort
    private let clock: C
    private var received: [UInt8] = []
    private var isClosed = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var reader: Task<Void, Never>?

    public init(port: any SerialPort, clock: C) {
        self.port = port
        self.clock = clock
    }

    var buffered: Int { received.count }
    var isWaiting: Bool { waiter != nil }

    public func open() throws(TransportError) {
        let bytes = try port.open()
        reader = Task { [weak self] in
            for await chunk in bytes {
                await self?.receive(chunk)
            }
            await self?.unplugged()
        }
    }

    public func close() {
        reader?.cancel()
        port.close()
    }

    public func setBaudRate(_ rate: Int) throws(TransportError) {
        try port.setBaudRate(rate)
    }

    public func setModemLines(dtr: Bool, rts: Bool) throws(TransportError) {
        try port.setModemLines(dtr: dtr, rts: rts)
    }

    public func write(_ bytes: [UInt8]) throws(TransportError) {
        try port.write(bytes)
    }

    public func read(timeout: Duration) async throws(TransportError) -> [UInt8] {
        if received.isEmpty, !isClosed {
            let clock = clock
            let timer = Task { [weak self] in
                guard (try? await clock.sleep(for: timeout)) != nil else { return }  // cancelled
                await self?.wake()
            }
            await withCheckedContinuation { waiter = $0 }
            timer.cancel()
        }
        guard !received.isEmpty || !isClosed else { throw .connectionLost }
        defer { received = [] }
        return received
    }

    private func receive(_ chunk: [UInt8]) {
        received += chunk
        wake()
    }

    private func unplugged() {
        isClosed = true
        wake()
    }

    private func wake() {
        waiter?.resume()
        waiter = nil
    }
}
