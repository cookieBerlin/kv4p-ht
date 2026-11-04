import KV4PSimulator
import KV4PTestSupport
import KV4PTransport
import Testing

@testable import KV4PRadio

/// Permissions the test sets and changes by hand.
@MainActor
final class FakePermissions: PermissionChecking {
    let changes: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private var states: [Permission: PermissionState]
    private(set) var requested: [Permission] = []

    init(_ states: [Permission: PermissionState] = [:]) {
        self.states = states
        (changes, continuation) = AsyncStream.makeStream()
    }

    func state(of permission: Permission) -> PermissionState {
        states[permission] ?? .granted
    }

    func request(_ permission: Permission) {
        requested.append(permission)
    }

    func set(_ permission: Permission, _ state: PermissionState) {
        setQuietly(permission, state)
        continuation.yield()
    }

    /// The system reports no change for Bluetooth outside a central.
    func setQuietly(_ permission: Permission, _ state: PermissionState) {
        states[permission] = state
    }
}

/// Asking for permissions when connecting, and what the app offers without them (ADR-0040).
@MainActor
@Suite("Radio view model: permissions")
struct RadioViewModelPermissionTests {
    static func model(
        _ permissions: FakePermissions,
        scanner: FakeBLEScanner? = nil,
        location: (any LocationProvider)? = nil,
        settings: MemorySettingsStore? = nil,
        microphone: FakeMicrophone? = nil
    ) -> RadioViewModel {
        RadioViewModel(
            makeController: { _, rxAudio in
                let clock = ManualClock()
                let transport = SimulatorTransport(simulator: RadioSimulator(scenario: .ble), clock: clock)
                return RadioController(transport: transport, clock: clock, rxAudio: rxAudio, microphone: microphone)
            },
            serialDevices: { ["/dev/cu.usbserial-0001"] },
            location: location,
            settings: settings,
            bluetoothScanner: scanner,
            permissions: permissions
        )
    }

    @Test("nothing is asked before connecting")
    func nothingAtStart() {
        let permissions = FakePermissions()
        _ = Self.model(permissions)
        #expect(permissions.requested.isEmpty)
    }

    @Test("connecting to a radio asks for the microphone and the location")
    func connectAsks() async {
        let permissions = FakePermissions()
        let model = Self.model(permissions)
        await model.connect()
        #expect(permissions.requested == [.microphone, .location])
    }

    @Test("connecting to the simulator asks for nothing")
    func simulatorAsksNothing() async {
        let permissions = FakePermissions()
        let alerts = FakeFailureAlerts(usesDialog: false)
        let model = RadioViewModel(
            makeController: { _, rxAudio in
                let clock = ManualClock()
                let transport = SimulatorTransport(simulator: RadioSimulator(scenario: .ble), clock: clock)
                return RadioController(transport: transport, clock: clock, rxAudio: rxAudio)
            },
            serialDevices: { [] },
            failureAlerts: alerts,
            permissions: permissions
        )
        model.selectedConnection = .simulator
        await model.connect()
        #expect(permissions.requested.isEmpty)
        #expect(alerts.prepared == 0)
    }

    @Test("the scan waits until Bluetooth is allowed, as it would ask for it")
    func scanWaits() async {
        let permissions = FakePermissions([.bluetooth: .notDetermined])
        let scanner = FakeBLEScanner()
        let model = Self.model(permissions, scanner: scanner)
        model.startBluetoothScan()
        #expect(scanner.started == 0)
        permissions.set(.bluetooth, .granted)
        #expect(await KV4PTestSupport.eventually { scanner.started == 1 })
        _ = model
    }

    @Test("without Bluetooth access, Bluetooth radios cannot be connected, USB and the simulator can")
    func bluetoothDenied() {
        let scanner = FakeBLEScanner()
        let model = Self.model(FakePermissions([.bluetooth: .denied]), scanner: scanner)
        model.startBluetoothScan()
        #expect(scanner.started == 0)
        #expect(model.isDenied(.bluetooth))
        #expect(model.isBluetoothBlocked)
        #expect(!model.canStartConnection)
        model.selectedConnection = .bluetoothDevice(RadioViewModelBluetoothTests.radio)
        #expect(model.isBluetoothBlocked)
        model.selectedConnection = .serial("/dev/cu.usbserial-0001")
        #expect(!model.isBluetoothBlocked)
        #expect(model.canStartConnection)
        model.selectedConnection = .simulator
        #expect(model.canStartConnection)
    }

    @Test("a permission refused while the app is open takes effect")
    func changes() async {
        let permissions = FakePermissions()
        let model = Self.model(permissions)
        #expect(!model.isDenied(.microphone))
        permissions.set(.microphone, .denied)
        #expect(await KV4PTestSupport.eventually { model.isDenied(.microphone) })
    }

    @Test("the answer to the Bluetooth request of a connection is noticed when it ends")
    func answerAfterConnecting() async {
        let permissions = FakePermissions([.bluetooth: .notDetermined])
        let scanner = FakeBLEScanner()
        let model = Self.model(permissions, scanner: scanner)
        model.startBluetoothScan()
        await model.connect()
        permissions.setQuietly(.bluetooth, .denied)
        await model.disconnect()
        #expect(model.isDenied(.bluetooth))
        #expect(scanner.started == 0)
        permissions.setQuietly(.bluetooth, .granted)
        await model.connect()
        await model.disconnect()
        #expect(!model.isDenied(.bluetooth))
        #expect(scanner.started == 1)
    }

    @Test("without location access, the beacon is off and cannot be turned on")
    func locationDenied() {
        var settings = AppSettings()
        settings.isBeaconEnabled = true
        let store = MemorySettingsStore(settings)
        let model = Self.model(
            FakePermissions([.location: .denied]),
            location: FakeLocation(),
            settings: store
        )
        #expect(!model.isBeaconEnabled)
        #expect(!model.canBeacon)
    }

    @Test("the beacon stays off when location access returns")
    func locationReturns() async {
        let permissions = FakePermissions()
        let model = Self.model(permissions, location: FakeLocation())
        model.isBeaconEnabled = true
        #expect(model.canBeacon)
        permissions.set(.location, .denied)
        #expect(await KV4PTestSupport.eventually { !model.isBeaconEnabled })
        permissions.set(.location, .granted)
        #expect(await KV4PTestSupport.eventually { model.canBeacon })
        #expect(!model.isBeaconEnabled)
    }

    @Test("the app can check again, as after a return from the system settings")
    func refresh() {
        let permissions = FakePermissions()
        let model = Self.model(permissions)
        permissions.set(.location, .denied)
        model.refreshPermissions()
        #expect(model.isDenied(.location))
    }

    @Test("each refused permission says what it stops", arguments: Permission.allCases)
    func messages(permission: Permission) {
        #expect(permission.deniedMessage.contains("not allowed"))
    }

    @Test("a microphone that does not start because access is denied says so")
    func microphoneDenied() async {
        let permissions = FakePermissions()
        let model = Self.model(permissions, microphone: FakeMicrophone(fails: true))
        model.callsign = "N0CALL"
        await model.connect()
        #expect(await RadioViewModelTests.eventually(model) { $0.isReady && $0.snapshot.isInSync })
        model.frequencyText = "146.52"
        await model.applyFrequency()
        #expect(await RadioViewModelTests.eventually(model) { $0.canTransmit && $0.snapshot.isInSync })
        permissions.setQuietly(.microphone, .denied)
        await model.pressPTT()
        #expect(model.message == Permission.microphone.deniedMessage)
    }
}
