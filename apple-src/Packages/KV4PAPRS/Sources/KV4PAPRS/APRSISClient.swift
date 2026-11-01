import Foundation
import Synchronization

/// A line-based TCP connection; the APRS-IS adapter implements it (`NetworkLineConnector`).
public protocol LineConnection: Sendable {
    /// Lines from the server without terminators; ends when the connection closes.
    var lines: AsyncStream<String> { get }
    /// Writes one line; the connection adds CR LF.
    func send(_ line: String) async throws
    func close()
}

public protocol LineConnector: Sendable {
    func connect(host: String, port: Int) async throws -> any LineConnection
}

/// What the app tells the APRS-IS connection.
public struct APRSISSettings: Equatable, Sendable {
    public var isEnabled: Bool
    /// Show APRS-IS packets near the filter location.
    public var isReceiveEnabled: Bool
    /// iGate: send lines (needs a verified login).
    public var isTransmitEnabled: Bool
    public var callsign: String
    public var server: APRSIS.Server?
    public var latitude: Double?
    public var longitude: Double?
    public var radiusKm: Double

    public init(
        isEnabled: Bool = false,
        isReceiveEnabled: Bool = false,
        isTransmitEnabled: Bool = false,
        callsign: String = "",
        server: APRSIS.Server? = APRSIS.Server(APRSIS.defaultServer),
        latitude: Double? = nil,
        longitude: Double? = nil,
        radiusKm: Double = 50
    ) {
        self.isEnabled = isEnabled
        self.isReceiveEnabled = isReceiveEnabled
        self.isTransmitEnabled = isTransmitEnabled
        self.callsign = callsign
        self.server = server
        self.latitude = latitude
        self.longitude = longitude
        self.radiusKm = radiusKm
    }
}

/// An APRS-IS connection as the view model uses it; `APRSISClient` implements it.
public protocol APRSInternetLink: Sendable {
    var received: AsyncStream<String> { get }
    var delivered: AsyncStream<APRSInternetRequest> { get }
    var isLoggedIn: Bool { get }
    func update(_ settings: APRSISSettings)
    func send(_ request: APRSInternetRequest, as callsign: String) -> Bool
}

/// The APRS-IS connection of the Android app (java-aprs `AprsIsClient`): logs in with passcode and filter, sends
/// queued lines (at most four) once logged in, delivers received packets, and reconnects with a backoff of 1 s to
/// 60 s. Settings changes reconnect; a new filter location only after moving 5 km.
public final class APRSISClient<C: Clock>: APRSInternetLink where C.Duration == Duration {
    public typealias Settings = APRSISSettings

    static var maximumPending: Int { 4 }
    static var maximumLineBytes: Int { 510 }
    static var timeout: Duration { .seconds(10) }
    static var initialReconnectDelay: Duration { .seconds(1) }
    static var maximumReconnectDelay: Duration { .seconds(60) }
    static var filterMovementKm: Double { 5 }

    /// Packet lines received from APRS-IS.
    public let received: AsyncStream<String>
    /// Lines sent to APRS-IS; confirm them with `APRSController.recordInternetTransmission`.
    public let delivered: AsyncStream<APRSInternetRequest>

    private enum Event {
        case connected(any LineConnection)
        case failed
        case line(String)
        case timeout
        case wake
    }

    private struct State {
        var settings = Settings()
        var generation = 0
        var pending: [APRSInternetRequest] = [] {
            didSet { pendingGeneration += 1 }
        }
        /// Counts queue changes, so a reconnect wait ends early for new lines (`pendingPacketGeneration`).
        var pendingGeneration = 0
        var isReconnectDue = false
        var isClosed = false
        var isLoggedIn = false
        var isWaitingToReconnect = false
        var session: AsyncStream<Event>.Continuation?
        var loopWake: AsyncStream<Void>.Continuation?
    }

    private let state = Mutex(State())
    private let software: String
    private let version: String
    private let connector: any LineConnector
    private let clock: C
    private let receivedContinuation: AsyncStream<String>.Continuation
    private let deliveredContinuation: AsyncStream<APRSInternetRequest>.Continuation
    private let loop: Mutex<Task<Void, Never>?> = Mutex(nil)

    public init(software: String, version: String, connector: any LineConnector, clock: C) {
        self.software = Self.singleWord(software)
        self.version = Self.singleWord(version)
        self.connector = connector
        self.clock = clock
        (received, receivedContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(256))
        (delivered, deliveredContinuation) = AsyncStream.makeStream()
        let (wakes, wake) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        state.withLock { $0.loopWake = wake }
        loop.withLock { $0 = Task { [weak self] in await self?.run(wakes) } }
    }

    deinit {
        close()
    }

    /// Logged in to a server.
    public var isLoggedIn: Bool { state.withLock { $0.isLoggedIn } }

    /// Between sessions, waiting for the reconnect delay.
    var isWaitingToReconnect: Bool { state.withLock { $0.isWaitingToReconnect } }

    /// Applies the settings like the setters of `AprsIsClient`.
    public func update(_ settings: Settings) {
        state.withLock { state in
            guard !state.isClosed else { return }
            var next = settings
            next.callsign = APRSIS.normalize(settings.callsign)
            if Self.sameLocation(state.settings, next) {
                next.latitude = state.settings.latitude
                next.longitude = state.settings.longitude
            }
            guard next != state.settings else { return }
            if !next.isEnabled || !next.isTransmitEnabled || next.callsign != state.settings.callsign {
                state.pending = []
            }
            state.settings = next
            state.generation += 1
            Self.wake(&state)
        }
    }

    /// `send`: queues a line while transmitting is enabled; a different callsign reconnects first.
    public func send(_ request: APRSInternetRequest, as callsign: String) -> Bool {
        let normalized = APRSIS.normalize(callsign)
        guard Self.isValid(line: request.line), Self.isValid(callsign: normalized) else { return false }
        return state.withLock { state in
            guard !state.isClosed, state.settings.isEnabled, state.settings.isTransmitEnabled,
                state.pending.count < Self.maximumPending || normalized != state.settings.callsign
            else { return false }
            if normalized != state.settings.callsign {
                state.settings.callsign = normalized
                state.generation += 1
                state.pending = []
            }
            state.pending.append(request)
            Self.wake(&state)
            return true
        }
    }

    public func close() {
        state.withLock { state in
            state.isClosed = true
            state.settings.isEnabled = false
            state.pending = []
            state.generation += 1
            Self.wake(&state)
        }
        loop.withLock { $0?.cancel() }
    }

    // MARK: Connection loop

    private func run(_ wakes: AsyncStream<Void>) async {
        var wakeups = wakes.makeAsyncIterator()
        var delay = Self.initialReconnectDelay
        while !Task.isCancelled {
            let (settings, generation) = state.withLock { ($0.settings, $0.generation) }
            guard settings.isEnabled, Self.isValid(callsign: settings.callsign), let server = settings.server else {
                guard await wakeups.next() != nil else { return }
                continue
            }
            let queued = state.withLock { $0.pendingGeneration }
            let loggedIn = await session(settings, server: server, generation: generation)
            if loggedIn {
                delay = Self.initialReconnectDelay
            }
            await wait(delay, generation: generation, queued: queued, wakeups: &wakeups)
            if !loggedIn {
                delay = min(delay * 2, Self.maximumReconnectDelay)
            }
        }
    }

    /// `awaitReconnect`: the delay, or less when the settings or the queue changed since the session started.
    private func wait(
        _ delay: Duration,
        generation: Int,
        queued: Int,
        wakeups: inout AsyncStream<Void>.Iterator
    ) async {
        let wake = state.withLock { state in
            state.isReconnectDue = false
            return state.loopWake
        }
        let clock = clock
        let timer = Task { [weak self] in
            guard (try? await clock.sleep(for: delay)) != nil else { return }
            self?.state.withLock { $0.isReconnectDue = true }
            wake?.yield()
        }
        state.withLock { $0.isWaitingToReconnect = true }
        defer {
            state.withLock { $0.isWaitingToReconnect = false }
            timer.cancel()
        }
        while state.withLock({
            !$0.isReconnectDue && !$0.isClosed && $0.generation == generation && $0.pendingGeneration == queued
        }) {
            guard await wakeups.next() != nil else { return }
        }
    }

    /// One connection: connect, greeting, login, then sending and receiving until it ends or the settings change.
    private func session(_ settings: Settings, server: APRSIS.Server, generation: Int) async -> Bool {
        let (events, sink) = AsyncStream.makeStream(of: Event.self)
        state.withLock { $0.session = sink }
        let connector = connector
        let connecting = Task {
            do {
                sink.yield(.connected(try await connector.connect(host: server.host, port: server.port)))
            } catch {
                sink.yield(.failed)
            }
        }
        var timer = startTimer(sink)
        var connection: (any LineConnection)?
        var reader: Task<Void, Never>?
        var isGreeted = false
        var loggedIn = false
        defer {
            connecting.cancel()
            timer.cancel()
            reader?.cancel()
            connection?.close()
            state.withLock {
                $0.session = nil
                $0.isLoggedIn = false
            }
        }
        for await event in events {
            guard state.withLock({ $0.generation == generation && !$0.isClosed }) else { return loggedIn }
            switch event {
            case .connected(let opened):
                connection = opened
                reader = Task {
                    for await line in opened.lines {
                        sink.yield(.line(line))
                    }
                    sink.finish()  // the connection closed
                }
                timer.cancel()
                timer = startTimer(sink)
            case .line where !isGreeted:
                isGreeted = true
                let passcode = settings.isTransmitEnabled ? APRSIS.passcode(settings.callsign) : -1
                let login = APRSIS.loginLine(
                    callsign: settings.callsign,
                    passcode: passcode,
                    software: software,
                    version: version,
                    receive: settings.isReceiveEnabled,
                    latitude: settings.latitude,
                    longitude: settings.longitude,
                    radiusKm: settings.radiusKm
                )
                guard await write(login, to: connection) else { return false }
                timer.cancel()
                timer = startTimer(sink)
            case .line(let line) where !loggedIn:
                switch Self.loginResponse(
                    line,
                    callsign: settings.callsign,
                    requireVerified: settings.isTransmitEnabled
                ) {
                case .accepted:
                    loggedIn = true
                    timer.cancel()
                    state.withLock { $0.isLoggedIn = true }
                    guard await flush(to: connection, generation: generation) else { return true }
                case .rejected:
                    return false
                case .other:
                    break
                }
            case .line(let line):
                if settings.isReceiveEnabled, !line.hasPrefix("#"), Self.isValid(line: line) {
                    receivedContinuation.yield(line)
                }
            case .wake:
                if loggedIn {
                    guard await flush(to: connection, generation: generation) else { return true }
                }
            case .failed, .timeout:
                return loggedIn
            }
        }
        return loggedIn
    }

    private func startTimer(_ sink: AsyncStream<Event>.Continuation) -> Task<Void, Never> {
        let clock = clock
        return Task {
            if (try? await clock.sleep(for: Self.timeout)) != nil {
                sink.yield(.timeout)
            }
        }
    }

    /// `transmitPendingPacket`: sends the queue in order; a line counts as delivered once written.
    private func flush(to connection: (any LineConnection)?, generation: Int) async -> Bool {
        while let next = state.withLock({ $0.generation == generation ? $0.pending.first : nil }) {
            guard await write(next.line, to: connection) else { return false }
            let removed = state.withLock { state in
                guard state.generation == generation, state.pending.first == next else { return false }
                state.pending.removeFirst()
                return true
            }
            if removed {
                deliveredContinuation.yield(next)
            }
        }
        return true
    }

    private func write(_ line: String, to connection: (any LineConnection)?) async -> Bool {
        do {
            try await connection?.send(line)
            return true
        } catch {
            return false
        }
    }

    // MARK: Rules

    private enum LoginResponse {
        case accepted, rejected, other
    }

    /// `awaitLogin`.
    private static func loginResponse(_ line: String, callsign: String, requireVerified: Bool) -> LoginResponse {
        let normalized = line.uppercased()
        if normalized.hasPrefix("# LOGRESP \(callsign.uppercased()) ") {
            let verified =
                normalized.contains(" VERIFIED") || (!requireVerified && normalized.contains(" UNVERIFIED"))
            return verified ? .accepted : .rejected
        }
        let rejected = ["# LOGRESP ", "# LOGIN", "# ERROR"].contains { normalized.hasPrefix($0) }
        return rejected ? .rejected : .other
    }

    private static func wake(_ state: inout State) {
        state.session?.yield(.wake)
        state.loopWake?.yield()
    }

    /// `isValidPacket`: one line of at most 510 bytes.
    static func isValid(line: String) -> Bool {
        !line.unicodeScalars.contains { $0 == "\r" || $0 == "\n" } && Java.latin1Bytes(line).count <= maximumLineBytes
    }

    /// `AX25_CALLSIGN`.
    static func isValid(callsign: String) -> Bool {
        callsign.wholeMatch(of: /[A-Z0-9]{3,6}(?:-[A-Z0-9]{1,2})?/) != nil
    }

    /// `singleWord`.
    static func singleWord(_ text: String) -> String {
        let trimmed = Java.trim(text)
        return trimmed.isEmpty ? "unknown" : trimmed.replacing(/\s+/, with: "_")
    }

    /// `sameFilterLocation`: both unset, or less than 5 km apart.
    private static func sameLocation(_ old: Settings, _ new: Settings) -> Bool {
        guard let oldLatitude = valid(old.latitude, 90), let oldLongitude = valid(old.longitude, 180),
            let newLatitude = valid(new.latitude, 90), let newLongitude = valid(new.longitude, 180)
        else {
            return [old.latitude, old.longitude, new.latitude, new.longitude].allSatisfy { $0 == nil }
        }
        return distanceKm(oldLatitude, oldLongitude, newLatitude, newLongitude) < filterMovementKm
    }

    private static func valid(_ value: Double?, _ limit: Double) -> Double? {
        value.flatMap { $0.isFinite && abs($0) <= limit ? $0 : nil }
    }

    /// `distanceKm`: haversine on a 6371 km sphere.
    static func distanceKm(_ fromLatitude: Double, _ fromLongitude: Double, _ toLatitude: Double, _ toLongitude: Double)
        -> Double
    {
        let radians = { (degrees: Double) in degrees * .pi / 180 }
        let latitudeDelta = radians(toLatitude - fromLatitude)
        let longitudeDelta = radians(toLongitude - fromLongitude)
        let a =
            sin(latitudeDelta / 2) * sin(latitudeDelta / 2) + cos(radians(fromLatitude)) * cos(radians(toLatitude))
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        let bounded = max(0, min(1, a))
        return 6371 * 2 * atan2(sqrt(bounded), sqrt(1 - bounded))
    }
}

extension APRSISClient where C == ContinuousClock {
    public convenience init(software: String, version: String, connector: any LineConnector) {
        self.init(software: software, version: version, connector: connector, clock: ContinuousClock())
    }
}
