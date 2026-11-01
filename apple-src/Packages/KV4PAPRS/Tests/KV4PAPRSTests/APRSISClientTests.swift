import KV4PTestSupport
import Synchronization
import Testing

@testable import KV4PAPRS

/// A fake APRS-IS server: every connect makes a connection the test talks through.
final class FakeConnector: LineConnector {
    final class Connection: LineConnection {
        let host: String
        let port: Int
        let lines: AsyncStream<String>
        private let continuation: AsyncStream<String>.Continuation
        private let written = Mutex<[String]>([])
        private let failsToSend: Bool

        init(host: String, port: Int, failsToSend: Bool) {
            self.host = host
            self.port = port
            self.failsToSend = failsToSend
            (lines, continuation) = AsyncStream.makeStream()
        }

        var sent: [String] { written.withLock { $0 } }

        func say(_ line: String) {
            continuation.yield(line)
        }

        func send(_ line: String) async throws {
            if failsToSend { throw Failure() }
            written.withLock { $0.append(line) }
        }

        func close() {
            continuation.finish()
        }
    }

    struct Failure: Error {}

    private let made = Mutex<[Connection]>([])
    private let refuses: Bool
    private let hangs: Bool
    private let failsToSend: Bool

    init(refuses: Bool = false, hangs: Bool = false, failsToSend: Bool = false) {
        self.refuses = refuses
        self.hangs = hangs
        self.failsToSend = failsToSend
    }

    var connections: [Connection] { made.withLock { $0 } }
    let attempts = Mutex(0)

    func connect(host: String, port: Int) async throws -> any LineConnection {
        attempts.withLock { $0 += 1 }
        if refuses { throw Failure() }
        if hangs {
            try await Task.sleep(for: .seconds(3600))
        }
        let connection = Connection(host: host, port: port, failsToSend: failsToSend)
        made.withLock { $0.append(connection) }
        return connection
    }
}

/// java-aprs `AprsIsClient`: login with passcode and filter, queued lines, reconnects.
@Suite("APRS-IS client")
struct APRSISClientTests {
    static let receiveOnly = APRSISClient<ManualClock>.Settings(
        isEnabled: true,
        isReceiveEnabled: true,
        isTransmitEnabled: false,
        callsign: "N0CALL"
    )
    static let request = APRSInternetRequest(line: "N1CALL>APRS,qAO,N0CALL:>status", eventId: 1)

    struct Setup {
        let clock = ManualClock()
        let connector: FakeConnector
        let client: APRSISClient<ManualClock>

        init(_ connector: FakeConnector = FakeConnector()) {
            self.connector = connector
            client = APRSISClient(software: "kv4p ht", version: "1.0", connector: connector, clock: clock)
        }

        /// Waits until the client waits to reconnect, then lets `seconds` pass.
        func reconnect(after seconds: Int) async {
            #expect(await eventually { client.isWaitingToReconnect })
            await clock.waitForSleepers(1)
            clock.advance(by: .seconds(seconds))
        }

        /// Waits for connection `index`, greets, checks the login and answers `response`.
        func login(_ index: Int = 0, response: String = "# logresp N0CALL verified, server T2EXAMPLE") async throws
            -> FakeConnector.Connection
        {
            #expect(await eventually { connector.connections.count > index })
            let connection = connector.connections[index]
            connection.say("# aprsc 2.1 example")
            #expect(await eventually { !connection.sent.isEmpty })
            connection.say("# server note")  // neither a response nor a rejection
            connection.say(response)
            return connection
        }
    }

    @Test("receive only: unverified login with a nearby filter; comments are not packets")
    func receiveOnly() async throws {
        let setup = Setup()
        var received = setup.client.received.makeAsyncIterator()
        setup.client.update(Self.receiveOnly)
        let connection = try await setup.login(response: "# logresp N0CALL unverified, server T2EXAMPLE")
        #expect(connection.host == "rotate.aprs2.net")
        #expect(connection.port == 14580)
        #expect(connection.sent == ["user N0CALL pass -1 vers kv4p_ht 1.0 filter m/50"])
        #expect(await eventually { setup.client.isLoggedIn })
        connection.say("# comment")
        connection.say("N1CALL>APRS,TCPIP*:>hello")
        #expect(await received.next() == "N1CALL>APRS,TCPIP*:>hello")
    }

    @Test("transmit needs a verified login; queued lines are sent and confirmed")
    func transmit() async throws {
        let setup = Setup()
        var delivered = setup.client.delivered.makeAsyncIterator()
        var settings = Self.receiveOnly
        settings.isTransmitEnabled = true
        setup.client.update(settings)
        #expect(setup.client.send(Self.request, as: "N0CALL"))
        let connection = try await setup.login()
        #expect(connection.sent.first == "user N0CALL pass 13023 vers kv4p_ht 1.0 filter m/50")
        #expect(await delivered.next() == Self.request)
        #expect(connection.sent.last == Self.request.line)
        #expect(setup.client.send(Self.request, as: "N0CALL"))
        #expect(await delivered.next() == Self.request)
    }

    @Test("an unverified login is not enough to transmit")
    func unverifiedTransmit() async throws {
        let setup = Setup()
        var settings = Self.receiveOnly
        settings.isTransmitEnabled = true
        setup.client.update(settings)
        _ = try await setup.login(response: "# logresp N0CALL unverified, server T2EXAMPLE")
        #expect(await eventually { setup.client.isWaitingToReconnect })
        #expect(!setup.client.isLoggedIn)
    }

    @Test("lines are refused when disabled, invalid, for an invalid callsign, or when four wait")
    func refusedLines() async throws {
        let setup = Setup(FakeConnector(hangs: true))
        #expect(!setup.client.send(Self.request, as: "N0CALL"))
        var settings = Self.receiveOnly
        settings.isTransmitEnabled = true
        setup.client.update(settings)
        #expect(!setup.client.send(APRSInternetRequest(line: "a\r\nb", eventId: nil), as: "N0CALL"))
        #expect(
            !setup.client.send(
                APRSInternetRequest(line: String(repeating: "x", count: 511), eventId: nil),
                as: "N0CALL"
            )
        )
        #expect(!setup.client.send(Self.request, as: "X"))
        for _ in 0..<4 {
            #expect(setup.client.send(Self.request, as: "N0CALL"))
        }
        #expect(!setup.client.send(Self.request, as: "N0CALL"))
        #expect(setup.client.send(Self.request, as: "N0CALL-7"))  // a new callsign drops the queue
        settings.isTransmitEnabled = false
        setup.client.update(settings)
        #expect(!setup.client.send(Self.request, as: "N0CALL-7"))
    }

    @Test("rejected logins retry after 1, 2, 4 … seconds; a session that ends retries after 1 s")
    func reconnects() async throws {
        let setup = Setup()
        setup.client.update(Self.receiveOnly)
        _ = try await setup.login(0, response: "# login by user not allowed")
        await setup.reconnect(after: 1)
        _ = try await setup.login(1, response: "# logresp N1CALL verified")
        await setup.reconnect(after: 1)
        for _ in 0..<100 { await Task.yield() }
        #expect(setup.connector.connections.count == 2)
        setup.clock.advance(by: .seconds(1))
        let third = try await setup.login(2, response: "# error")
        await setup.reconnect(after: 4)
        let fourth = try await setup.login(3)
        #expect(await eventually { setup.client.isLoggedIn })
        fourth.close()
        #expect(await eventually { !setup.client.isLoggedIn })
        await setup.reconnect(after: 1)
        #expect(await eventually { setup.connector.connections.count == 5 })
        third.close()
    }

    @Test("a server that does not answer times out after 10 s; a refused connection backs off")
    func timeouts() async throws {
        let hanging = Setup(FakeConnector(hangs: true))
        hanging.client.update(Self.receiveOnly)
        await hanging.clock.waitForSleepers(1)
        hanging.clock.advance(by: .seconds(10))
        await hanging.reconnect(after: 1)
        #expect(await eventually { hanging.connector.attempts.withLock { $0 } == 2 })
        let refused = Setup(FakeConnector(refuses: true))
        refused.client.update(Self.receiveOnly)
        await refused.reconnect(after: 1)
        #expect(await eventually { refused.connector.attempts.withLock { $0 } == 2 })
        let silent = Setup()
        silent.client.update(Self.receiveOnly)
        #expect(await eventually { silent.connector.connections.count == 1 })
        await silent.clock.waitForSleepers(1)
        silent.clock.advance(by: .seconds(10))
        await silent.reconnect(after: 1)
        #expect(await eventually { silent.connector.connections.count == 2 })
    }

    @Test("a failed send ends the session; the line stays queued")
    func sendFails() async throws {
        let setup = Setup(FakeConnector(failsToSend: true))
        var settings = Self.receiveOnly
        settings.isTransmitEnabled = true
        setup.client.update(settings)
        #expect(await eventually { setup.connector.connections.count == 1 })
        setup.connector.connections[0].say("# greeting")
        #expect(await eventually { setup.client.isWaitingToReconnect })
        #expect(!setup.client.isLoggedIn)
    }

    @Test("a new filter location reconnects only after moving 5 km")
    func filterLocation() async throws {
        let setup = Setup()
        var settings = Self.receiveOnly
        settings.latitude = 49.0583
        settings.longitude = -72.0292
        setup.client.update(settings)
        let first = try await setup.login()
        #expect(first.sent == ["user N0CALL pass -1 vers kv4p_ht 1.0 filter r/49.05830/-72.02920/50"])
        #expect(await eventually { setup.client.isLoggedIn })
        settings.latitude = 49.08
        setup.client.update(settings)
        settings.server = APRSIS.Server("euro.example.net")
        settings.latitude = 49.2
        setup.client.update(settings)
        #expect(await eventually { setup.connector.connections.count == 2 })
        #expect(setup.connector.connections[1].host == "euro.example.net")
        settings.latitude = nil
        setup.client.update(settings)
        #expect(await eventually { setup.connector.connections.count == 3 })
    }

    @Test("disabled or closed, the client does not connect")
    func disabledAndClosed() async throws {
        let setup = Setup()
        var settings = Self.receiveOnly
        settings.callsign = "X"
        setup.client.update(settings)
        settings.callsign = "N0CALL"
        settings.isEnabled = false
        setup.client.update(settings)
        for _ in 0..<100 { await Task.yield() }
        #expect(setup.connector.connections.isEmpty)
        settings.isEnabled = true
        setup.client.update(settings)
        _ = try await setup.login()
        #expect(await eventually { setup.client.isLoggedIn })
        setup.client.close()
        #expect(await eventually { !setup.client.isLoggedIn })
        setup.client.update(settings)
        #expect(!setup.client.send(Self.request, as: "N0CALL"))
    }
}

@Suite("APRS-IS client clock")
struct APRSISClientClockTests {
    @Test("the client runs on the continuous clock by default")
    func continuousClock() async {
        let client = APRSISClient(software: "", version: " ", connector: FakeConnector())
        client.update(.init(isEnabled: true, isReceiveEnabled: true, callsign: "N0CALL"))
        #expect(await eventually { !client.isLoggedIn })
        client.close()
        #expect(APRSISClient<ContinuousClock>.singleWord("") == "unknown")
    }
}

/// Waits until `condition` holds, for up to five seconds (parallel tests share the cooperative pool).
func eventually(_ condition: () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        await Task.yield()
    }
    return await condition()
}
