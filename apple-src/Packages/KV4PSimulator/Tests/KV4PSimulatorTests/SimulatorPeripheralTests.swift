import KV4PProtocol
import KV4PTestSupport
import Synchronization
import Testing

@testable import KV4PSimulator

/// A `CBPeripheralManager` stand-in that accepts every notification.
final class FakePeripheralManager: BLEPeripheralManager {
    let events: AsyncStream<PeripheralEvent>
    private let continuation: AsyncStream<PeripheralEvent>.Continuation
    private let log = Mutex<[PeripheralCommand]>([])

    init() {
        (events, continuation) = AsyncStream.makeStream()
        continuation.yield(.powerState(.poweredOn))
    }

    var commands: [PeripheralCommand] { log.withLock { $0 } }

    var notified: [UInt8] {
        commands.flatMap { command -> [UInt8] in
            guard case .notify(let chunk) = command else { return [] }
            return chunk
        }
    }

    func perform(_ command: PeripheralCommand) {
        log.withLock { $0.append(command) }
        switch command {
        case .addService: continuation.yield(.serviceAdded(true))
        case .notify: continuation.yield(.notified(true))
        case .startAdvertising, .stopAdvertising: break
        }
    }

    func emit(_ event: PeripheralEvent) {
        continuation.yield(event)
    }

    func finish() {
        continuation.finish()
    }

    func waitUntil(_ condition: (FakePeripheralManager) throws -> Bool) async rethrows {
        while try !condition(self) {
            await Task.yield()
        }
    }
}

@Suite("Simulator peripheral")
struct SimulatorPeripheralTests {
    @Test("advertises, serves a central and ticks simulated time")
    func session() async throws {
        let clock = ManualClock()
        let manager = FakePeripheralManager()
        let peripheral = SimulatorPeripheral(manager: manager, clock: clock)
        let running = Task { await peripheral.run() }
        await manager.waitUntil { $0.commands.contains(.startAdvertising) }
        manager.emit(.subscribed(maximumUpdateLength: 182))
        await manager.waitUntil { (try? events($0.notified).count) == 1 }
        manager.emit(.write(FrameEncoder.desiredState(desiredState(sequence: 1))))
        await manager.waitUntil { (try? events($0.notified).count) == 3 }
        await clock.waitForSleepers(1)
        clock.advance(by: .milliseconds(500))
        await manager.waitUntil { (try? events($0.notified).states.count) == 2 }
        #expect(await peripheral.link.isSubscribed)
        manager.finish()
        await running.value
    }

    @Test("the convenience initializer uses the BLE scenario")
    func defaults() async {
        let peripheral = SimulatorPeripheral(manager: FakePeripheralManager())
        #expect(await peripheral.link.simulator.scenario.windowSize == 4096)
    }
}
