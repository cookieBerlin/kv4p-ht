/// The serial port adapter (POSIX/termios); forwards only (ADR-0018).
public protocol SerialPort: Sendable {
    /// Opens the port raw at 115200 8N1. The stream yields received bytes and finishes when the port closes or
    /// fails.
    func open() throws(TransportError) -> AsyncStream<[UInt8]>
    /// Changes the speed of an open port, e.g. for the ESP32 bootloader.
    func setBaudRate(_ rate: Int) throws(TransportError)
    /// Sets DTR and RTS together.
    func setModemLines(dtr: Bool, rts: Bool) throws(TransportError)
    func write(_ bytes: [UInt8]) throws(TransportError)
    func close()
}

/// `RadioTransport` over USB serial (macOS), 115200 8N1 (`docs/apple/03-protocol-spec.md` §1).
public actor SerialTransport<C: Clock>: RadioTransport where C.Duration == Duration {
    /// How long RTS holds the ESP32 in reset (`EN` low), as in the Android flashing reset.
    public static var resetPulse: Duration { .milliseconds(100) }

    private nonisolated let streams = TransportStreams()
    private let port: any SerialPort
    private let resetOnConnect: Bool
    private let clock: C
    private var reader: Task<Void, Never>?

    /// With `resetOnConnect`, the ESP32 restarts and sends `HELLO`; otherwise only a device that boots after the
    /// port opened sends one.
    public init(port: any SerialPort, resetOnConnect: Bool = false, clock: C) {
        self.port = port
        self.resetOnConnect = resetOnConnect
        self.clock = clock
    }

    public nonisolated var states: AsyncStream<TransportState> { streams.states }

    public nonisolated var incoming: AsyncStream<[UInt8]> { streams.incoming }

    public func connect() async throws(TransportError) {
        guard streams.state != .connected else { return }
        streams.publish(.connecting)
        do {
            let bytes = try port.open()
            try await configureLines()
            startReading(bytes)
            streams.publish(.connected)
        } catch {
            port.close()
            streams.publish(.failed(error))
            throw error
        }
    }

    public func send(_ bytes: [UInt8]) async throws(TransportError) {
        guard streams.state == .connected else { throw .notConnected }
        do {
            try port.write(bytes)
        } catch {
            fail(error)
            throw error
        }
    }

    public func disconnect() async {
        guard streams.state == .connected else { return }
        streams.publish(.disconnected)
        stopReading()
    }

    /// DTR and RTS both set, as the Android app does; the reset pulse holds `EN` low with RTS alone.
    private func configureLines() async throws(TransportError) {
        if resetOnConnect {
            try port.setModemLines(dtr: false, rts: true)
            do {
                try await clock.sleep(for: Self.resetPulse)
            } catch {
                throw .notConnected
            }
        }
        try port.setModemLines(dtr: true, rts: true)
    }

    private func startReading(_ bytes: AsyncStream<[UInt8]>) {
        let streams = streams
        reader = Task { [weak self] in
            for await chunk in bytes {
                streams.deliver(chunk)
            }
            await self?.portClosed()
        }
    }

    private func portClosed() {
        if streams.state == .connected {
            fail(.connectionLost)
        }
    }

    private func fail(_ error: TransportError) {
        streams.publish(.failed(error))
        stopReading()
    }

    private func stopReading() {
        reader?.cancel()
        reader = nil
        port.close()
    }
}

extension SerialTransport where C == ContinuousClock {
    public init(port: any SerialPort, resetOnConnect: Bool = false) {
        self.init(port: port, resetOnConnect: resetOnConnect, clock: ContinuousClock())
    }
}
