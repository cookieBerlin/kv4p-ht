import KV4PProtocol
import KV4PTransport

public enum RadioStatus: Equatable, Sendable {
    case disconnected
    case connecting
    /// Connected; the device sends `HELLO` next.
    case waitingForHello
    /// `HELLO` accepted; the radio can be controlled.
    case ready
    case failed(RadioFailure)
}

public enum RadioFailure: Error, Equatable, Sendable {
    case transport(TransportError)
    case helloTimeout
    /// `HELLO` could not be decoded; the firmware needs an update.
    case invalidHello
    /// Older than the firmware the Android app ships (`FirmwareUtils.PACKAGED_FIRMWARE_VER`).
    case firmwareTooOld(UInt16)
    /// The SA818 did not answer at boot; any radio configuration would stall the firmware.
    case radioModuleNotFound
}

public enum RadioError: Error, Equatable, Sendable {
    case notReady
    case frequencyOutOfRange(Float)
}

/// Everything the UI shows about the radio.
public struct RadioSnapshot: Equatable, Sendable {
    public var status: RadioStatus
    public var firmware: FirmwareVersion?
    /// The latest state reported by the device.
    public var deviceState: DeviceState?
    public var desired: HostDesiredState
    /// The device applied the last desired state.
    public var isInSync: Bool

    /// S-meter bars, see `SMeter`.
    public var sMeter: Int { SMeter.value(rssi: deviceState?.latestRssi ?? 0) }
}

/// Connects to the radio, runs the handshake and keeps the device in the desired state (as the Android
/// `RadioAudioService` does): HELLO validation, flow control, desired-state sync.
public actor RadioController<C: Clock> where C.Duration == Duration {
    /// Firmware the Android app ships; older firmware is refused.
    public static var minimumFirmwareVersion: UInt16 { 17 }
    public static var defaultHelloTimeout: Duration { .seconds(10) }

    public nonisolated let snapshots: AsyncStream<RadioSnapshot>
    public private(set) var snapshot: RadioSnapshot
    private let snapshotContinuation: AsyncStream<RadioSnapshot>.Continuation
    private let transport: any RadioTransport
    private let clock: C
    private let helloTimeout: Duration
    private let window = FlowControlWindow()
    private let frames: AsyncStream<[UInt8]>
    private let outbox: AsyncStream<[UInt8]>.Continuation
    private var parser = KISSParser()
    private var desiredState = DesiredStateController()
    private var tasks: [Task<Void, Never>] = []
    private var helloTimer: Task<Void, Never>?
    /// Numbers connection attempts, so a timer of an earlier attempt cannot fail a later one.
    private var attempt = 0

    public init(transport: any RadioTransport, clock: C, helloTimeout: Duration = defaultHelloTimeout) {
        self.transport = transport
        self.clock = clock
        self.helloTimeout = helloTimeout
        snapshot = RadioSnapshot(status: .disconnected, desired: DesiredStateController().desired, isInSync: false)
        (snapshots, snapshotContinuation) = AsyncStream.makeStream()
        (frames, outbox) = AsyncStream.makeStream()
    }

    deinit {
        tasks.forEach { $0.cancel() }
        helloTimer?.cancel()
        outbox.finish()
        snapshotContinuation.finish()
    }

    // MARK: Session

    public func connect() async {
        startTasks()
        parser = KISSParser()
        desiredState.attach()
        publish(.connecting)
        do {
            try await transport.connect()
        } catch {
            fail(.transport(error))
            return
        }
        guard snapshot.status == .connecting else { return }  // HELLO arrived during connect
        publish(.waitingForHello)
        attempt += 1
        let clock = clock
        let timeout = helloTimeout
        let current = attempt
        helloTimer = Task { [weak self] in
            try? await clock.sleep(for: timeout)
            await self?.helloTimedOut(attempt: current)
        }
    }

    public func disconnect() async {
        helloTimer?.cancel()
        await transport.disconnect()
        desiredState.detach()
        publish(.disconnected)
    }

    /// The sender and both transport streams are consumed for the lifetime of the controller.
    private func startTasks() {
        guard tasks.isEmpty else { return }
        let frames = frames
        let incoming = transport.incoming
        let states = transport.states
        tasks = [
            Task { [weak self] in
                for await frame in frames {
                    await self?.send(frame)
                }
            },
            Task { [weak self] in
                for await chunk in incoming {
                    await self?.receive(chunk)
                }
            },
            Task { [weak self] in
                for await state in states {
                    await self?.transportChanged(state)
                }
            },
        ]
    }

    // MARK: Control

    /// Tunes RX and TX; both must be within the range of the radio module.
    public func tune(rx: Float, tx: Float, memoryId: Int32 = -1) throws(RadioError) {
        guard snapshot.status == .ready, let firmware = desiredState.firmware else { throw .notReady }
        let range = firmware.minRadioFreq...firmware.maxRadioFreq
        for frequency in [rx, tx] where !range.contains(frequency) {
            throw .frequencyOutOfRange(frequency)
        }
        update { state in
            state.setRxFrequency(rx)
            state.setTxFrequency(tx)
            state.setMemoryId(memoryId)
        }
    }

    /// Applies several changes as one desired state, e.g. `update { $0.setSquelch(4) }`.
    public func update(_ changes: (inout DesiredStateController) -> Void) {
        desiredState.beginUpdate()
        changes(&desiredState)
        desiredState.endUpdate()
        flush()
    }

    // MARK: Device → host

    private func receive(_ chunk: [UInt8]) async {
        for frame in parser.process(chunk) {
            switch frame {
            case .command(.hello, let payload):
                await handleHello(payload)
            case .command(.deviceState, let payload):
                if let state = try? DeviceState(decoding: payload) {
                    desiredState.update(state)
                    flush()
                }
            case .command(.windowUpdate, let payload):
                if let update = try? WindowUpdate(decoding: payload) {
                    await window.enlarge(by: Int(update.size))
                }
            default:
                break  // RX audio, digital voice, AX.25 and debug output come with later milestones
            }
        }
    }

    /// `RadioAudioService.validateHello`.
    private func handleHello(_ payload: [UInt8]) async {
        helloTimer?.cancel()
        guard let hello = try? Hello(decoding: payload) else { return fail(.invalidHello) }
        let version = hello.version
        guard version.version >= Self.minimumFirmwareVersion else { return fail(.firmwareTooOld(version.version)) }
        desiredState.seed(version)
        guard version.radioModuleStatus != .notFound else { return fail(.radioModuleNotFound) }
        desiredState.seed(hello.deviceState)
        desiredState.markReady()
        desiredState.openAudio()
        publish(.ready)
        // The window of this session applies before the first desired state is queued.
        await window.set(Int(version.windowSize))
        flush()
    }

    private func helloTimedOut(attempt timedOut: Int) {
        guard timedOut == attempt, snapshot.status == .waitingForHello else { return }
        fail(.helloTimeout)
    }

    private func transportChanged(_ state: TransportState) {
        if case .failed(let error) = state, snapshot.status != .disconnected {
            fail(.transport(error))
        }
    }

    // MARK: Host → device

    /// Queues the pending desired states; the sender writes them in order within the flow-control window.
    private func flush() {
        for state in desiredState.takeOutgoing() {
            outbox.yield(FrameEncoder.desiredState(state))
        }
        publish(snapshot.status)
    }

    /// Frames are sent one at a time, in order.
    private func send(_ frame: [UInt8]) async {
        // Failures mean the transport is gone; the next HELLO resyncs the state.
        try? await window.reserve(frame.count)
        try? await transport.send(frame)
    }

    private func fail(_ failure: RadioFailure) {
        helloTimer?.cancel()
        desiredState.detach()
        publish(.failed(failure))
    }

    private func publish(_ status: RadioStatus) {
        let next = RadioSnapshot(
            status: status,
            firmware: desiredState.firmware,
            deviceState: desiredState.deviceState,
            desired: desiredState.desired,
            isInSync: desiredState.isAppliedStateInSync
        )
        guard next != snapshot else { return }
        snapshot = next
        snapshotContinuation.yield(next)
    }
}

extension RadioController where C == ContinuousClock {
    public init(transport: any RadioTransport, helloTimeout: Duration = defaultHelloTimeout) {
        self.init(transport: transport, clock: ContinuousClock(), helloTimeout: helloTimeout)
    }
}
