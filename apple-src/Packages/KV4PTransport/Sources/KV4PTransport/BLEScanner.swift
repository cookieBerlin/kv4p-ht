import Foundation

/// A kv4p HT seen by a scan.
public struct BLEDevice: Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    /// The name and the end of the ID, so that radios of the same name differ.
    public var label: String { "\(name) (\(id.uuidString.suffix(4)))" }
}

/// Finds the radios in range, without connecting to one (ADR-0038).
public protocol BLEScanning: Sendable {
    /// The radios found so far, updated as they appear; ending the stream stops the scan.
    func scan() -> AsyncStream<[BLEDevice]>
}

public struct BLEScanner: BLEScanning {
    private let makeCentral: @Sendable () -> any BLECentral

    /// `makeCentral`: a central of its own, as a connection takes over the events of its central.
    public init(makeCentral: @escaping @Sendable () -> any BLECentral) {
        self.makeCentral = makeCentral
    }

    public func scan() -> AsyncStream<[BLEDevice]> {
        let central = makeCentral()
        let (stream, continuation) = AsyncStream.makeStream(of: [BLEDevice].self, bufferingPolicy: .bufferingNewest(1))
        let task = Task {
            var devices: [UUID: BLEDevice] = [:]
            for await event in central.events {
                switch event {
                case .powerState(.poweredOn):
                    central.perform(.scan)
                case .advertised(let device) where devices[device.id] != device:
                    devices[device.id] = device
                    continuation.yield(devices.values.sorted { $0.label < $1.label })
                default:
                    break
                }
            }
        }
        continuation.onTermination = { _ in
            task.cancel()
            central.perform(.stopScan)
        }
        return stream
    }
}
