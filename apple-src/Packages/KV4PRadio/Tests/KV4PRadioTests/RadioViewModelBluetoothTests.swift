import Foundation
import KV4PSimulator
import KV4PTestSupport
import KV4PTransport
import Synchronization
import Testing

@testable import KV4PRadio

/// A scan the tests feed by hand.
final class FakeBLEScanner: BLEScanning {
    private let continuation = Mutex<AsyncStream<[BLEDevice]>.Continuation?>(nil)
    private let counts = Mutex((started: 0, ended: 0))

    var started: Int { counts.withLock { $0.started } }
    var running: Int { counts.withLock { $0.started - $0.ended } }

    func scan() -> AsyncStream<[BLEDevice]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [BLEDevice].self)
        continuation.onTermination = { [counts] _ in counts.withLock { $0.ended += 1 } }
        counts.withLock { $0.started += 1 }
        self.continuation.withLock { $0 = continuation }
        return stream
    }

    func find(_ devices: [BLEDevice]) {
        continuation.withLock { _ = $0?.yield(devices) }
    }
}

/// Choosing a radio over Bluetooth and remembering it (ADR-0038).
@MainActor
@Suite("Radio view model: Bluetooth radios")
struct RadioViewModelBluetoothTests {
    static let radio = BLEDevice(
        id: UUID(uuidString: "00000000-0000-0000-0000-00000000B2C3") ?? UUID(),
        name: "kv4p HT"
    )
    static let other = BLEDevice(
        id: UUID(uuidString: "00000000-0000-0000-0000-00000000D4E5") ?? UUID(),
        name: "kv4p HT"
    )

    final class Connections: Sendable {
        private let log = Mutex<[RadioViewModel.Connection]>([])
        var all: [RadioViewModel.Connection] { log.withLock { $0 } }
        func add(_ connection: RadioViewModel.Connection) { log.withLock { $0.append(connection) } }
    }

    static func model(
        scanner: FakeBLEScanner? = FakeBLEScanner(),
        settings: MemorySettingsStore = MemorySettingsStore(),
        scenario: Scenario = .ble,
        connections: Connections = Connections()
    ) -> RadioViewModel {
        RadioViewModel(
            makeController: { connection, rxAudio in
                connections.add(connection)
                let clock = ManualClock()
                let transport = SimulatorTransport(simulator: RadioSimulator(scenario: scenario), clock: clock)
                return RadioController(transport: transport, clock: clock, rxAudio: rxAudio)
            },
            serialDevices: { ["/dev/cu.usbserial-0001"] },
            settings: settings,
            bluetoothScanner: scanner
        )
    }

    @Test("the radios found are listed after the first-found choice")
    func lists() async {
        let scanner = FakeBLEScanner()
        let model = Self.model(scanner: scanner)
        model.startBluetoothScan()
        scanner.find([Self.radio, Self.other])
        #expect(
            await eventually {
                model.connections == [
                    .bluetooth, .bluetoothDevice(Self.radio), .bluetoothDevice(Self.other),
                    .serial("/dev/cu.usbserial-0001"), .simulator,
                ]
            }
        )
        #expect(model.connections[0].label == "Bluetooth (first radio found)")
        #expect(model.connections[1].label == "kv4p HT (B2C3)")
        #expect(Set(model.connections.map(\.id)).count == 5)
    }

    @Test("there is one scan at a time, only while it is wanted")
    func oneScan() async {
        let scanner = FakeBLEScanner()
        let model = Self.model(scanner: scanner)
        model.stopBluetoothScan()
        #expect(scanner.started == 0)
        model.startBluetoothScan()
        model.startBluetoothScan()
        #expect(scanner.started == 1)
        model.stopBluetoothScan()
        #expect(await eventually { scanner.running == 0 })
    }

    @Test("connecting ends the scan, disconnecting starts it again")
    func connectionPausesScan() async {
        let scanner = FakeBLEScanner()
        let model = Self.model(scanner: scanner)
        model.startBluetoothScan()
        await model.connect()
        #expect(await eventually { scanner.running == 0 })
        #expect(await RadioViewModelTests.eventually(model) { $0.isReady })
        #expect(scanner.running == 0)
        await model.disconnect()
        #expect(scanner.started == 2)
        #expect(scanner.running == 1)
        model.stopBluetoothScan()
    }

    @Test("a failed connection starts the scan again, if wanted")
    func failureResumesScan() async {
        let scanner = FakeBLEScanner()
        let model = Self.model(scanner: scanner, scenario: .noRadioModule)
        model.startBluetoothScan()
        await model.connect()
        #expect(await RadioViewModelTests.eventually(model) { $0.canConnect && $0.message != nil })
        #expect(await eventually { scanner.started == 2 && scanner.running == 1 })
        model.stopBluetoothScan()
    }

    @Test("without a scanner, nothing is scanned")
    func noScanner() {
        let model = Self.model(scanner: nil)
        model.startBluetoothScan()
        #expect(model.connections == [.bluetooth, .serial("/dev/cu.usbserial-0001"), .simulator])
    }

    @Test("the connection uses the chosen radio")
    func connectsToChoice() async {
        let connections = Connections()
        let model = Self.model(connections: connections)
        model.selectedConnection = .bluetoothDevice(Self.radio)
        await model.connect()
        #expect(connections.all == [.bluetoothDevice(Self.radio)])
        await model.disconnect()
    }

    @Test("the chosen radio is remembered, and listed even before a scan finds it")
    func remembers() {
        let settings = MemorySettingsStore()
        let model = Self.model(settings: settings)
        model.selectedConnection = .bluetoothDevice(Self.radio)
        #expect(settings.settings.bluetoothRadio == Self.radio)

        let restored = Self.model(settings: settings)
        #expect(restored.selectedConnection == .bluetoothDevice(Self.radio))
        #expect(restored.connections.contains(.bluetoothDevice(Self.radio)))
    }

    @Test("a remembered radio takes the name a scan finds")
    func renames() async {
        var stored = AppSettings()
        stored.bluetoothRadio = Self.radio
        let scanner = FakeBLEScanner()
        let model = Self.model(scanner: scanner, settings: MemorySettingsStore(stored))
        let renamed = BLEDevice(id: Self.radio.id, name: "Base")
        model.startBluetoothScan()
        scanner.find([renamed])
        #expect(await eventually { model.connections.contains(.bluetoothDevice(renamed)) })
        #expect(model.connections.filter { $0.label.hasSuffix("(B2C3)") }.count == 1)
        #expect(model.selectedConnection == .bluetoothDevice(renamed))
        #expect(model.settings.bluetoothRadio == renamed)
        model.stopBluetoothScan()
    }

    @Test("choosing the first radio found forgets the radio; USB and the simulator keep it")
    func forgets() {
        let settings = MemorySettingsStore()
        let model = Self.model(settings: settings)
        model.selectedConnection = .bluetoothDevice(Self.radio)
        model.selectedConnection = .simulator
        #expect(settings.settings.bluetoothRadio == Self.radio)
        #expect(model.connections.contains(.bluetoothDevice(Self.radio)))
        model.selectedConnection = .bluetooth
        #expect(settings.settings.bluetoothRadio == nil)
        #expect(!model.connections.contains(.bluetoothDevice(Self.radio)))
    }
}
