import KV4PSimulator
import KV4PTestSupport
import Testing

@testable import KV4PProtocol
@testable import KV4PRadio

/// Packets the radio decoded on air (KISS DATA frames) reach the app.
@Suite("AX.25 forwarding")
struct AX25ForwardingTests {
    @Test("received AX.25 frames are forwarded once the radio is ready")
    func forwards() async throws {
        let clock = ManualClock()
        let transport = SimulatorTransport(simulator: RadioSimulator(scenario: .ble), clock: clock)
        let controller = RadioController(transport: transport, clock: clock)
        var snapshots = controller.snapshots.makeAsyncIterator()
        var frames = controller.receivedFrames.makeAsyncIterator()
        await controller.connect()
        _ = try #require(await snapshots.next { $0.status == .ready })
        await transport.hear([0x82, 0xA0, 0x41])
        #expect(await frames.next() == [0x82, 0xA0, 0x41])
    }

    @Test("frames before HELLO are ignored")
    func beforeHello() async throws {
        let transport = ScriptedTransport()
        let controller = RadioController(transport: transport, clock: ManualClock())
        var snapshots = controller.snapshots.makeAsyncIterator()
        var frames = controller.receivedFrames.makeAsyncIterator()
        await controller.connect()
        transport.streams.deliver(DeviceFrameEncoder.ax25([0x01]))
        var simulator = RadioSimulator(scenario: .ble)
        transport.streams.deliver(simulator.connect(at: .zero))
        _ = await snapshots.next { $0.status == .ready }
        transport.streams.deliver(DeviceFrameEncoder.ax25([0x02]))
        #expect(await frames.next() == [0x02])
    }
}
