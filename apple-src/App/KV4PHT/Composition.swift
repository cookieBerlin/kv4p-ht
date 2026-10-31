import KV4PRadio
import KV4PSimulator
import KV4PTransport

/// Composition root: wires the OS adapters to the radio stack. All behaviour lives in the packages.
@MainActor
enum Composition {
    static func makeViewModel() -> RadioViewModel {
        RadioViewModel(
            makeController: { RadioController(transport: transport(for: $0)) },
            serialDevices: serialDevices
        )
    }

    private static func transport(for connection: RadioViewModel.Connection) -> any RadioTransport {
        switch connection {
        case .bluetooth:
            BLETransport(central: CoreBluetoothCentral())
        case .serial(let path):
            serialTransport(path)
        case .simulator:
            SimulatorTransport()
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
