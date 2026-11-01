import Foundation

/// `CBManagerState`, with the same raw values.
public enum BLEPowerState: Int, Equatable, Sendable {
    case unknown = 0
    case resetting = 1
    case unsupported = 2
    case unauthorized = 3
    case poweredOff = 4
    case poweredOn = 5
}

/// The TX characteristic as discovered by the adapter.
public struct BLECharacteristics: Equatable, Sendable {
    public var supportsWriteWithoutResponse: Bool
    /// `maximumWriteValueLength(for: .withoutResponse)`.
    public var maximumWriteWithoutResponseLength: Int
    /// `maximumWriteValueLength(for: .withResponse)`.
    public var maximumWriteWithResponseLength: Int

    public init(
        supportsWriteWithoutResponse: Bool,
        maximumWriteWithoutResponseLength: Int,
        maximumWriteWithResponseLength: Int
    ) {
        self.supportsWriteWithoutResponse = supportsWriteWithoutResponse
        self.maximumWriteWithoutResponseLength = maximumWriteWithoutResponseLength
        self.maximumWriteWithResponseLength = maximumWriteWithResponseLength
    }
}

/// CoreBluetooth callbacks, as reported by the adapter.
public enum BLEEvent: Equatable, Sendable {
    case powerState(BLEPowerState)
    /// A peripheral advertising the KV4P service.
    case discovered(UUID)
    /// The same peripheral with its name, for the list of radios (ADR-0038).
    case advertised(BLEDevice)
    case connected
    case failedToConnect
    case disconnected
    /// Service discovery finished; whether the KV4P service exists.
    case serviceDiscovered(Bool)
    /// Characteristic discovery finished; `nil` if TX or RX is missing.
    case characteristicsDiscovered(BLECharacteristics?)
    case notificationsEnabled(Bool)
    /// A notification of the RX characteristic.
    case value([UInt8])
    /// A write was issued; `canSendWriteWithoutResponse` right after it.
    case wrote(canSendMore: Bool)
    /// `peripheralIsReady(toSendWriteWithoutResponse:)` or the response of a write.
    case readyToWrite
}

/// CoreBluetooth calls for the adapter to execute.
public enum BLECommand: Equatable, Sendable {
    /// Scan for peripherals advertising the KV4P service.
    case scan
    case stopScan
    case connect(UUID)
    case discoverService
    case discoverCharacteristics
    /// Subscribe to the RX characteristic.
    case enableNotifications
    /// Write to the TX characteristic.
    case write([UInt8], withResponse: Bool)
    case cancelConnection
}

/// The BLE connection sequence (`docs/apple/03-protocol-spec.md` §1.1) and write queue, as a pure state machine
/// (ADR-0018).
public struct BLELink: Sendable {
    private enum Phase: Equatable {
        case idle
        case waitingForPower
        case scanning
        case connecting
        case discoveringService
        case discoveringCharacteristics
        case subscribing(BLECharacteristics)
        case connected(BLECharacteristics)
        case failed(TransportError)
    }

    private var phase = Phase.idle
    private var power = BLEPowerState.unknown
    private var target: UUID?
    private var pending: [UInt8] = []
    private var canWrite = true

    public init() {}

    public var state: TransportState {
        switch phase {
        case .idle: .disconnected
        case .connected: .connected
        case .failed(let error): .failed(error)
        default: .connecting
        }
    }

    /// Connects to `target`, or to the first peripheral found.
    public mutating func connect(to target: UUID?) -> [BLECommand] {
        switch phase {
        case .idle, .failed: break
        default: return []
        }
        self.target = target
        pending = []
        canWrite = true
        guard power == .poweredOn else {
            phase = .waitingForPower
            return []
        }
        phase = .scanning
        return [.scan]
    }

    public mutating func disconnect() -> [BLECommand] {
        let previous = phase
        phase = .idle
        pending = []
        switch previous {
        case .idle, .failed, .waitingForPower: return []
        case .scanning: return [.stopScan]
        default: return [.cancelConnection]
        }
    }

    /// Queues bytes for the TX characteristic; ignored unless connected.
    public mutating func send(_ bytes: [UInt8]) -> [BLECommand] {
        guard case .connected = phase else { return [] }
        pending += bytes
        return flush()
    }

    public mutating func handle(_ event: BLEEvent) -> [BLECommand] {
        switch (event, phase) {
        case (.powerState(let state), _):
            return powerChanged(state)
        case (.discovered(let peripheral), .scanning) where target == nil || target == peripheral:
            phase = .connecting
            return [.stopScan, .connect(peripheral)]
        case (.connected, .connecting):
            phase = .discoveringService
            return [.discoverService]
        case (.failedToConnect, .connecting):
            phase = .failed(.connectionFailed)
            return []
        case (.serviceDiscovered(true), .discoveringService):
            phase = .discoveringCharacteristics
            return [.discoverCharacteristics]
        case (.serviceDiscovered(false), .discoveringService),
            (.characteristicsDiscovered(nil), .discoveringCharacteristics):
            phase = .failed(.serviceNotFound)
            return [.cancelConnection]
        case (.characteristicsDiscovered(let characteristics?), .discoveringCharacteristics):
            phase = .subscribing(characteristics)
            return [.enableNotifications]
        case (.notificationsEnabled(true), .subscribing(let characteristics)):
            phase = .connected(characteristics)
            return flush()
        case (.notificationsEnabled(false), .subscribing):
            phase = .failed(.subscriptionFailed)
            return [.cancelConnection]
        case (.wrote(let canSendMore), .connected(let characteristics)):
            canWrite = canSendMore && characteristics.supportsWriteWithoutResponse
            return flush()
        case (.readyToWrite, .connected):
            canWrite = true
            return flush()
        case (.disconnected, .idle):
            return []
        case (.disconnected, _):
            phase = .failed(.connectionLost)
            pending = []
            return []
        default:
            return []
        }
    }

    private mutating func powerChanged(_ state: BLEPowerState) -> [BLECommand] {
        power = state
        switch (state, phase) {
        case (.poweredOn, .waitingForPower):
            phase = .scanning
            return [.scan]
        case (.unsupported, _), (.unauthorized, _), (.poweredOff, _):
            switch phase {
            case .idle, .failed: break
            default: phase = .failed(.bluetoothUnavailable(state))
            }
            return []
        default:
            return []
        }
    }

    /// Writes the next chunk if the adapter can take it.
    private mutating func flush() -> [BLECommand] {
        guard case .connected(let characteristics) = phase, canWrite, !pending.isEmpty else { return [] }
        let withoutResponse = characteristics.supportsWriteWithoutResponse
        let length =
            withoutResponse
            ? characteristics.maximumWriteWithoutResponseLength : characteristics.maximumWriteWithResponseLength
        let chunk = Array(pending.prefix(length))
        pending.removeFirst(chunk.count)
        canWrite = false
        return [.write(chunk, withResponse: !withoutResponse)]
    }
}
