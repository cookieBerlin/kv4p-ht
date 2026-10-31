import Foundation
import Synchronization

@testable import KV4PTransport

/// A CoreBluetooth stand-in that answers each command like a kv4p HT, unless told otherwise.
final class FakeCentral: BLECentral {
    static let device = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA") ?? UUID()

    let events: AsyncStream<BLEEvent>
    private let continuation: AsyncStream<BLEEvent>.Continuation
    private let log = Mutex<[BLECommand]>([])
    private let responses: @Sendable (BLECommand) -> [BLEEvent]

    init(
        power: BLEPowerState = .poweredOn,
        responses: @escaping @Sendable (BLECommand) -> [BLEEvent] = FakeCentral.kv4p
    ) {
        (events, continuation) = AsyncStream.makeStream()
        self.responses = responses
        continuation.yield(.powerState(power))
    }

    static let characteristics = BLECharacteristics(
        supportsWriteWithoutResponse: true,
        maximumWriteWithoutResponseLength: 244,
        maximumWriteWithResponseLength: 512
    )

    @Sendable static func kv4p(_ command: BLECommand) -> [BLEEvent] {
        switch command {
        case .scan: [.discovered(device)]
        case .connect: [.connected]
        case .discoverService: [.serviceDiscovered(true)]
        case .discoverCharacteristics: [.characteristicsDiscovered(characteristics)]
        case .enableNotifications: [.notificationsEnabled(true)]
        case .write: [.wrote(canSendMore: true)]
        case .cancelConnection: [.disconnected]
        case .stopScan: []
        }
    }

    var commands: [BLECommand] { log.withLock { $0 } }

    func perform(_ command: BLECommand) {
        log.withLock { $0.append(command) }
        responses(command).forEach { continuation.yield($0) }
    }

    func emit(_ event: BLEEvent) {
        continuation.yield(event)
    }

    /// Waits until `command` was performed.
    func waitFor(_ command: BLECommand) async {
        while !commands.contains(command) {
            await Task.yield()
        }
    }
}
