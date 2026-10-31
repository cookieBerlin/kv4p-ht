import KV4PProtocol
import KV4PTransport
import Testing

@testable import KV4PSimulator

/// The GATT peripheral side of the simulator (ADR-0014 B), as a pure state machine (ADR-0018).
@Suite("Peripheral link")
struct PeripheralLinkTests {
    /// A link whose service is advertised and whose central subscribed with 20-byte notifications.
    static func subscribed() -> (PeripheralLink, hello: [PeripheralCommand]) {
        var link = PeripheralLink(simulator: RadioSimulator(scenario: .ble))
        _ = link.handle(.powerState(.poweredOn), at: .zero)
        _ = link.handle(.serviceAdded(true), at: .zero)
        let hello = link.handle(.subscribed(maximumUpdateLength: 20), at: .ms(10))
        return (link, hello)
    }

    /// Concatenates notified chunks, acknowledging each, until the link waits.
    static func drain(_ link: inout PeripheralLink, _ commands: [PeripheralCommand], at time: Duration) -> [UInt8] {
        var bytes: [UInt8] = []
        var next = commands
        while case .notify(let chunk)? = next.last {
            bytes += chunk
            next = link.handle(.notified(true), at: time)
        }
        return bytes
    }

    @Test("the service is added once powered on, then advertised")
    func advertise() {
        var link = PeripheralLink(simulator: RadioSimulator())
        #expect(link.handle(.powerState(.unknown), at: .zero).isEmpty)
        #expect(link.handle(.powerState(.poweredOn), at: .zero) == [.addService])
        #expect(link.handle(.serviceAdded(true), at: .zero) == [.startAdvertising])
        #expect(link.isAdvertising)
        #expect(link.handle(.powerState(.poweredOn), at: .zero).isEmpty)
    }

    @Test("a service that cannot be added is reported")
    func serviceFails() {
        var link = PeripheralLink(simulator: RadioSimulator())
        _ = link.handle(.powerState(.poweredOn), at: .zero)
        #expect(link.handle(.serviceAdded(false), at: .zero).isEmpty)
        #expect(link.failed)
        #expect(!link.isAdvertising)
    }

    @Test("advertising that fails to start is reported")
    func advertisingFails() {
        var link = PeripheralLink(simulator: RadioSimulator())
        _ = link.handle(.powerState(.poweredOn), at: .zero)
        _ = link.handle(.serviceAdded(true), at: .zero)
        #expect(link.handle(.advertisingStarted(error: nil), at: .zero).isEmpty)
        #expect(link.isAdvertising)
        #expect(!link.failed)
        #expect(link.handle(.advertisingStarted(error: "not permitted"), at: .zero).isEmpty)
        #expect(!link.isAdvertising)
        #expect(link.failed)
    }

    @Test("a subscription stops advertising and sends HELLO in chunks of the update length")
    func subscribe() throws {
        var (link, commands) = Self.subscribed()
        #expect(commands.first == .stopAdvertising)
        #expect(
            commands.dropFirst().allSatisfy { if case .notify(let chunk) = $0 { chunk.count == 20 } else { false } }
        )
        let bytes = Self.drain(&link, commands, at: .ms(10))
        guard case .hello(let hello) = try #require(try events(bytes).first) else {
            Issue.record("no HELLO")
            return
        }
        #expect(hello.version.windowSize == 4096)
        #expect(link.isSubscribed)
    }

    @Test("writes reach the simulator and its answer is notified")
    func write() throws {
        var (link, hello) = Self.subscribed()
        _ = Self.drain(&link, hello, at: .ms(10))
        let frame = FrameEncoder.desiredState(desiredState(sequence: 1))
        let reply = Self.drain(&link, link.handle(.write(frame), at: .ms(20)), at: .ms(20))
        #expect(try events(reply).windowUpdates == [UInt32(frame.count)])
        #expect(link.simulator.deviceState.radio.sequence == 1)
    }

    @Test("a refused notification is resent when the queue has room again")
    func backPressure() {
        var (link, hello) = Self.subscribed()
        guard case .notify(let first)? = hello.last else {
            Issue.record("no notification")
            return
        }
        #expect(link.handle(.notified(false), at: .ms(10)).isEmpty)
        #expect(link.handle(.readyToUpdate, at: .ms(11)) == [.notify(first)])
        #expect(link.handle(.readyToUpdate, at: .ms(12)).isEmpty)
    }

    @Test("time drives status reports while subscribed")
    func statusReports() throws {
        var (link, hello) = Self.subscribed()
        _ = Self.drain(&link, hello, at: .ms(10))
        _ = Self.drain(
            &link,
            link.handle(.write(FrameEncoder.desiredState(desiredState(sequence: 1))), at: .ms(20)),
            at: .ms(20)
        )
        let report = Self.drain(&link, link.advance(to: .ms(500)), at: .ms(500))
        #expect(try events(report).states.count == 1)
    }

    @Test("unsubscribing disconnects the session and advertises again")
    func unsubscribe() {
        var (link, _) = Self.subscribed()
        #expect(link.handle(.unsubscribed, at: .ms(20)) == [.startAdvertising])
        #expect(!link.isSubscribed)
        #expect(link.handle(.write([0xC0]), at: .ms(30)).isEmpty)
        #expect(link.advance(to: .seconds(2)).isEmpty)
        #expect(link.handle(.unsubscribed, at: .seconds(3)).isEmpty)
        #expect(link.handle(.notified(true), at: .seconds(3)).isEmpty)
    }

    @Test("a second central is ignored while one is subscribed")
    func singleSession() {
        var (link, _) = Self.subscribed()
        #expect(link.handle(.subscribed(maximumUpdateLength: 100), at: .ms(20)).isEmpty)
    }

    @Test("powering off ends the session; powering on adds the service again")
    func powerCycle() {
        var (link, _) = Self.subscribed()
        #expect(link.handle(.powerState(.poweredOff), at: .ms(20)).isEmpty)
        #expect(!link.isSubscribed)
        #expect(!link.isAdvertising)
        #expect(link.handle(.powerState(.poweredOn), at: .ms(30)) == [.addService])
    }
}
