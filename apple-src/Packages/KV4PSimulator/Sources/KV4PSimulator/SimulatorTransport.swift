import KV4PTransport

/// How often simulated time advances while a host is connected.
let simulatorTick = Duration.milliseconds(10)

/// `RadioTransport` to an in-process `RadioSimulator` (ADR-0014 A), so the app runs and is tested without hardware.
///
/// Time comes from `clock`, measured from the creation of the transport (power-on); a ticker advances the simulator
/// every `tick` while connected.
public actor SimulatorTransport<C: Clock>: RadioTransport where C.Duration == Duration {
    public static var tick: Duration { simulatorTick }

    public private(set) var simulator: RadioSimulator
    private nonisolated let streams = TransportStreams()
    private let clock: C
    private let powerOn: C.Instant
    private var ticker: Task<Void, Never>?

    public init(simulator: RadioSimulator = RadioSimulator(), clock: C) {
        self.simulator = simulator
        self.clock = clock
        powerOn = clock.now
    }

    deinit {
        ticker?.cancel()
    }

    public nonisolated var states: AsyncStream<TransportState> { streams.states }

    public nonisolated var incoming: AsyncStream<[UInt8]> { streams.incoming }

    public func connect() async throws(TransportError) {
        guard streams.state != .connected else { return }
        streams.publish(.connecting)
        streams.publish(.connected)
        streams.deliver(simulator.connect(at: elapsed))
        startTicking()
    }

    public func send(_ bytes: [UInt8]) async throws(TransportError) {
        guard streams.state == .connected else { throw .notConnected }
        streams.deliver(simulator.receive(bytes, at: elapsed))
    }

    public func disconnect() async {
        guard streams.state == .connected else { return }
        ticker?.cancel()
        ticker = nil
        _ = simulator.disconnect(at: elapsed)
        streams.publish(.disconnected)
    }

    /// An AX.25 packet (without FCS) received on air.
    public func hear(_ packet: [UInt8]) {
        streams.deliver(simulator.hear(packet, at: elapsed))
    }

    private var elapsed: Duration { powerOn.duration(to: clock.now) }

    private func startTicking() {
        let clock = clock
        ticker = Task { [weak self] in
            while (try? await clock.sleep(for: Self.tick)) != nil {
                await self?.advance()
            }
        }
    }

    private func advance() {
        streams.deliver(simulator.advance(to: elapsed))
    }
}

extension SimulatorTransport where C == ContinuousClock {
    public init(simulator: RadioSimulator = RadioSimulator()) {
        self.init(simulator: simulator, clock: ContinuousClock())
    }
}
