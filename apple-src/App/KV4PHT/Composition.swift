import KV4PAudio
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
            simulateSignal: { [simulator] in await simulator.transport?.setCarrier($0 ? Carrier() : nil) }
        )
    }

    private static func transport(for connection: RadioViewModel.Connection) -> any RadioTransport {
        switch connection {
        case .bluetooth:
            return BLETransport(central: CoreBluetoothCentral())
        case .serial(let path):
            return serialTransport(path)
        case .simulator:
            let transport = SimulatorTransport()
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
