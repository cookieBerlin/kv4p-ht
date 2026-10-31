/// The `CBPeripheralManager` adapter: reports callbacks as events and executes commands (ADR-0018).
public protocol BLEPeripheralManager: Sendable {
    /// Callbacks, starting with the power state; one consumer.
    var events: AsyncStream<PeripheralEvent> { get }
    func perform(_ command: PeripheralCommand)
}

/// Serves `RadioSimulator` as a BLE peripheral with the KV4P GATT service (ADR-0014 B), so the real BLE path of
/// a host can be tested without hardware.
public actor SimulatorPeripheral<C: Clock> where C.Duration == Duration {
    public private(set) var link: PeripheralLink
    private let manager: any BLEPeripheralManager
    private let clock: C
    private let powerOn: C.Instant

    public init(manager: any BLEPeripheralManager, simulator: RadioSimulator = RadioSimulator(scenario: .ble), clock: C)
    {
        self.manager = manager
        self.clock = clock
        link = PeripheralLink(simulator: simulator)
        powerOn = clock.now
    }

    /// Serves until the adapter's events finish or the task is cancelled.
    public func run() async {
        let events = manager.events
        let clock = clock
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await event in events {
                    await self.handle(event)
                }
            }
            group.addTask {
                while (try? await clock.sleep(for: simulatorTick)) != nil {
                    await self.advance()
                }
            }
            await group.next()
            group.cancelAll()
        }
    }

    private var elapsed: Duration { powerOn.duration(to: clock.now) }

    private func handle(_ event: PeripheralEvent) {
        link.handle(event, at: elapsed).forEach(manager.perform)
    }

    private func advance() {
        link.advance(to: elapsed).forEach(manager.perform)
    }
}

extension SimulatorPeripheral where C == ContinuousClock {
    public init(manager: any BLEPeripheralManager, simulator: RadioSimulator = RadioSimulator(scenario: .ble)) {
        self.init(manager: manager, simulator: simulator, clock: ContinuousClock())
    }
}
