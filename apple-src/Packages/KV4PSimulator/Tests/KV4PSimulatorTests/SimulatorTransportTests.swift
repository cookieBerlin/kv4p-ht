import KV4PProtocol
import KV4PTestSupport
import KV4PTransport
import Testing

@testable import KV4PSimulator

@Suite("Simulator transport")
struct SimulatorTransportTests {
    @Test("connect reports connected, then the device sends HELLO")
    func connect() async throws {
        let transport = SimulatorTransport(clock: ManualClock())
        try await transport.connect()
        try await transport.connect()
        #expect(await collect(2, from: transport.states) == [.connecting, .connected])
        var incoming = transport.incoming.makeAsyncIterator()
        let hello = try events(try #require(await incoming.next()))
        #expect(hello.count == 1)
        guard case .hello(let message) = hello.first else {
            Issue.record("no HELLO")
            return
        }
        #expect(message.version.version == 17)
    }

    @Test("host frames are answered and time drives the status reports")
    func statusReports() async throws {
        let clock = ManualClock()
        let transport = SimulatorTransport(simulator: RadioSimulator(scenario: .ble), clock: clock)
        var incoming = transport.incoming.makeAsyncIterator()
        try await transport.connect()
        _ = await incoming.next()
        let frame = FrameEncoder.desiredState(desiredState(sequence: 1))
        try await transport.send(frame)
        let reply = try events(try #require(await incoming.next()))
        #expect(reply.windowUpdates == [UInt32(frame.count)])
        #expect(reply.states.map(\.radio.sequence) == [1])
        await clock.waitForSleepers(1)
        clock.advance(by: .milliseconds(500))
        #expect(try events(try #require(await incoming.next())).states.count == 1)
    }

    @Test("the TX watchdog fires as time passes")
    func watchdog() async throws {
        let clock = ManualClock()
        let transport = SimulatorTransport(clock: clock)
        var incoming = transport.incoming.makeAsyncIterator()
        try await transport.connect()
        _ = await incoming.next()
        try await transport.send(
            FrameEncoder.desiredState(desiredState(sequence: 1, flags: [.pttRequested, .txAllowed]))
        )
        #expect(try events(try #require(await incoming.next())).states.last?.mode == .tx)
        await clock.waitForSleepers(1)
        clock.advance(by: .milliseconds(778))
        #expect(try events(try #require(await incoming.next())).states.last?.mode == .stopped)
        #expect(await transport.simulator.deviceState.mode == .stopped)
    }

    @Test("send needs a connection")
    func sendWhileDisconnected() async {
        let transport = SimulatorTransport(clock: ManualClock())
        await #expect(throws: TransportError.notConnected) { try await transport.send([0xC0]) }
    }

    @Test("disconnect stops the session and a reconnect sends HELLO again")
    func reconnect() async throws {
        let transport = SimulatorTransport()
        var incoming = transport.incoming.makeAsyncIterator()
        try await transport.connect()
        _ = await incoming.next()
        await transport.disconnect()
        await transport.disconnect()
        #expect(await collect(3, from: transport.states) == [.connecting, .connected, .disconnected])
        try await transport.connect()
        guard case .hello = try events(try #require(await incoming.next())).first else {
            Issue.record("no HELLO")
            return
        }
    }

    @Test("packets heard on air reach the host")
    func hear() async throws {
        let transport = SimulatorTransport(clock: ManualClock())
        var incoming = transport.incoming.makeAsyncIterator()
        try await transport.connect()
        _ = await incoming.next()
        await transport.hear([0x41, 0x42])
        #expect(try events(try #require(await incoming.next())) == [.ax25([0x41, 0x42])])
    }
}
