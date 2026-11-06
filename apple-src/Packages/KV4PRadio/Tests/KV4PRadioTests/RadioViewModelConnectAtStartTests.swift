import KV4PTestSupport
import Testing

@testable import KV4PRadio

/// Connecting by itself at the start, to the radio chosen last.
@MainActor
@Suite("Radio view model: connect at start")
struct RadioViewModelConnectAtStartTests {
    private static func model(
        _ permissions: FakePermissions = FakePermissions(),
        settings: MemorySettingsStore = MemorySettingsStore()
    ) -> RadioViewModel {
        RadioViewModelPermissionTests.model(permissions, settings: settings)
    }

    @Test("it is on by default, and the choice is saved and restored")
    func saved() {
        let store = MemorySettingsStore()
        let model = Self.model(settings: store)
        #expect(model.connectsAtStart)
        model.connectsAtStart = false
        #expect(!store.settings.connectsAtStart)
        #expect(!Self.model(settings: store).connectsAtStart)
    }

    @Test("a chosen Bluetooth radio is connected")
    func chosenRadio() async {
        let model = Self.model()
        model.selectedConnection = .bluetoothDevice(RadioViewModelBluetoothTests.radio)
        await model.connectAtStart()
        #expect(await RadioViewModelTests.eventually(model) { $0.isReady })
    }

    @Test("the simulator is connected when it was chosen")
    func simulator() async {
        let setup = RadioViewModelSimulatorTests.Setup()
        setup.model.selectedConnection = .simulator
        await setup.model.connectAtStart()
        #expect(await RadioViewModelTests.eventually(setup.model) { $0.isReady })
    }

    @Test("without a chosen radio, nothing is connected, as the first one found may be anyone's")
    func noChosenRadio() async {
        let model = Self.model()
        #expect(model.selectedConnection == .bluetooth)
        await model.connectAtStart()
        #expect(model.canConnect)
    }

    @Test("switched off, nothing is connected")
    func off() async {
        let model = Self.model()
        model.selectedConnection = .bluetoothDevice(RadioViewModelBluetoothTests.radio)
        model.connectsAtStart = false
        await model.connectAtStart()
        #expect(model.canConnect)
    }

    @Test("without Bluetooth access, nothing is connected")
    func blocked() async {
        let model = Self.model(FakePermissions([.bluetooth: .denied]))
        model.selectedConnection = .bluetoothDevice(RadioViewModelBluetoothTests.radio)
        model.refreshPermissions()
        await model.connectAtStart()
        #expect(model.canConnect)
    }

    @Test("only the first start connects, not a window that opens again")
    func once() async {
        let model = Self.model()
        model.selectedConnection = .bluetoothDevice(RadioViewModelBluetoothTests.radio)
        await model.connectAtStart()
        #expect(await RadioViewModelTests.eventually(model) { $0.isReady })
        await model.disconnect()
        await model.connectAtStart()
        #expect(model.canConnect)
    }
}
