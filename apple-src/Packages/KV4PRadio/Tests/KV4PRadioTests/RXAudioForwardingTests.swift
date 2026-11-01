import KV4PAudio
import KV4PSimulator
import KV4PTestSupport
import Synchronization
import Testing

@testable import KV4PProtocol
@testable import KV4PRadio

/// Records what the controller hands to the audio player.
final class RecordingSink: RXAudioSink {
    enum Event: Equatable {
        case block([UInt8])
        case reset
    }

    let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation

    init() {
        (events, continuation) = AsyncStream.makeStream()
    }

    func receive(block: [UInt8]) {
        continuation.yield(.block(block))
    }

    func reset() {
        continuation.yield(.reset)
    }
}

@Suite("RX audio forwarding")
struct RXAudioForwardingTests {
    static let block: [UInt8] = [0x10, 0x00, 0x00, 0x00, 0x77]

    @Test("RX_AUDIO blocks reach the sink once the radio is ready")
    func forwardsBlocks() async throws {
        var simulator = RadioSimulator(scenario: .ble)
        let transport = ScriptedTransport()
        let sink = RecordingSink()
        let controller = RadioController(transport: transport, clock: ManualClock(), rxAudio: sink)
        var snapshots = controller.snapshots.makeAsyncIterator()
        var events = sink.events.makeAsyncIterator()
        await controller.connect()
        transport.streams.deliver(DeviceFrameEncoder.rxAudio([0xFF]))  // before HELLO: ignored
        transport.streams.deliver(simulator.connect(at: .zero))
        _ = await snapshots.next { $0.status == .ready }
        transport.streams.deliver(DeviceFrameEncoder.rxAudio(Self.block))
        #expect(await events.next() == .block(Self.block))
        await controller.disconnect()
        #expect(await events.next() == .reset)
    }

    @Test("a failure discards the buffered audio")
    func failureResets() async {
        let transport = ScriptedTransport()
        let sink = RecordingSink()
        let controller = RadioController(transport: transport, clock: ManualClock(), rxAudio: sink)
        var events = sink.events.makeAsyncIterator()
        await controller.connect()
        transport.streams.publish(.failed(.connectionLost))
        #expect(await events.next() == .reset)
    }

    @Test("the simulator's carrier is audible end to end")
    func endToEnd() async throws {
        var scenario = Scenario.ble
        scenario.carrier = Carrier()
        let clock = ManualClock()
        let transport = SimulatorTransport(simulator: RadioSimulator(scenario: scenario), clock: clock)
        let player = RXAudioPlayer(buffer: JitterBuffer(prefill: 1, capacity: 4096), fadesIn: false)
        let controller = RadioController(transport: transport, clock: clock, rxAudio: player)
        var snapshots = controller.snapshots.makeAsyncIterator()
        await controller.connect()
        let ready = try #require(await snapshots.next { $0.status == .ready && $0.isInSync })
        #expect(ready.deviceState?.radio.flags.contains(.squelched) == false)
        while player.statistics.buffered < KV4P.audioBlockSamples {
            await clock.waitForSleepers(1)
            clock.advance(by: SimulatorTransport<ManualClock>.tick)
            await Task.yield()
        }
        let output = [Float](unsafeUninitializedCapacity: 249) { buffer, count in
            player.render(into: buffer)
            count = 249
        }
        #expect(output.contains { abs($0) > 0.1 })
    }
}
