import Foundation
import KV4PAPRS
import KV4PAudio
import KV4PPersistence
import KV4PRadio
import KV4PSimulator
import KV4PTransport

/// Composition root: wires the OS adapters to the radio stack. All behaviour lives in the packages.
@MainActor
enum Composition {
    /// The simulator of the current connection, for the simulated signal.
    private static let simulator = SimulatorBox()

    static func makeViewModel() -> RadioViewModel {
        RadioViewModel(
            makeController: {
                RadioController(transport: transport(for: $0), rxAudio: $1, microphone: AVAudioEngineInput())
            },
            serialDevices: serialDevices,
            audioOutput: AVAudioEngineOutput(),
            simulateSignal: { [simulator] in await simulator.transport?.setCarrier($0 ? .freeDVVoice : nil) },
            memories: memoryRepository(),
            location: CoreLocationProvider(),
            internet: APRSISClient(software: "kv4p-ht", version: appVersion, connector: NetworkLineConnector())
        )
    }

    /// `CFBundleShortVersionString`, sent in the APRS-IS login.
    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    /// The memories live in the app's Application Support folder; without it the app runs without memories.
    private static func memoryRepository() -> (any MemoryRepository)? {
        let folder = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try? SwiftDataMemoryRepository(storeURL: folder.appending(path: "Memories.store"))
    }

    private static func transport(for connection: RadioViewModel.Connection) -> any RadioTransport {
        switch connection {
        case .bluetooth:
            return BLETransport(central: CoreBluetoothCentral())
        case .serial(let path):
            return serialTransport(path)
        case .simulator:
            let transport = SimulatorTransport(simulator: RadioSimulator(scenario: .freeDV))
            simulator.transport = transport
            return transport
        }
    }

    #if os(macOS)
        /// The radio restarts on connect so that it sends HELLO.
        private static func serialTransport(_ path: String) -> any RadioTransport {
            SerialTransport(port: POSIXSerialPort(path: path), resetOnConnect: true)
        }

        private static func serialDevices() -> [String] {
            POSIXSerialPort.devices()
        }
    #else
        private static func serialTransport(_ path: String) -> any RadioTransport {
            SimulatorTransport()
        }

        private static func serialDevices() -> [String] {
            []
        }
    #endif
}

@MainActor
private final class SimulatorBox: Sendable {
    var transport: SimulatorTransport<ContinuousClock>?
}
