import KV4PAudio
import KV4PPersistence
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
    /// The TX frequency is outside the ham band (`TXBand`).
    case transmitNotAllowed
    /// No microphone, or access to it was denied.
    case microphoneUnavailable
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
    /// Scanning the memories (`startScan`).
    public var isScanning = false
    /// Counts the snapshots of one controller, so a reader can drop stale ones.
    public var revision = 0

    /// S-meter bars, see `SMeter`.
    public var sMeter: Int { SMeter.value(rssi: deviceState?.latestRssi ?? 0) }

    /// PTT is requested; the device reports `TX_ACTIVE` once it transmits.
    public var isTransmitting: Bool { desired.flags.contains(.pttRequested) }
}

/// Connects to the radio, runs the handshake and keeps the device in the desired state (as the Android
/// `RadioAudioService` does): HELLO validation, flow control, desired-state sync, RX audio to `rxAudio`, and PTT with
/// the `microphone` as TX audio.
public actor RadioController<C: Clock> where C.Duration == Duration {
    /// Firmware the Android app ships; older firmware is refused.
    public static var minimumFirmwareVersion: UInt16 { 17 }
    public static var defaultHelloTimeout: Duration { .seconds(10) }
    /// `RUNAWAY_TX_TIMEOUT_SEC`: the app ends PTT after this time, before the firmware's own limit.
    public static var runawayTXTimeout: Duration { .seconds(180) }
    /// `SCAN_SQUELCHED_ADVANCE_DELAY_MS`: how long the squelch stays closed before the scan moves on.
    public static var scanAdvanceDelay: Duration { .milliseconds(250) }
    /// `DEFAULT_SCAN_SQUELCH`: used while scanning when the squelch is open (0).
    public static var defaultScanSquelch: UInt8 { 7 }

    public nonisolated let snapshots: AsyncStream<RadioSnapshot>
    public private(set) var snapshot: RadioSnapshot
    private let snapshotContinuation: AsyncStream<RadioSnapshot>.Continuation
    private let transport: any RadioTransport
    private let clock: C
    private let helloTimeout: Duration
    private let rxAudio: (any RXAudioSink)?
    private let microphone: (any AudioInput)?
    private var txEncoder = TXAudioEncoder()
    /// Numbers transmissions, so late microphone samples and timers of an earlier one are ignored.
    private var transmission = 0
    private var isCapturing = false
    private var capture: Task<Void, Never>?
    private var runawayTimer: Task<Void, Never>?
    /// The memories being scanned; `nil` while not scanning.
    private var scanList: [ChannelMemory]?
    private var scanBaseSquelch: UInt8 = 0
    /// The memory tuned last, -1 for a plain frequency.
    private var activeMemoryId: Int32 = -1
    private var scanTimer: Task<Void, Never>?
    private var scanTimerMemory: Int32 = -1
    /// Numbers scan timers, so a cancelled one cannot advance.
    private var scanTimerGeneration = 0
    private let window = FlowControlWindow()
    private let frames: AsyncStream<[UInt8]>
    private let outbox: AsyncStream<[UInt8]>.Continuation
    private var parser = KISSParser()
    private var desiredState = DesiredStateController()
    private var tasks: [Task<Void, Never>] = []
    private var helloTimer: Task<Void, Never>?
    /// Numbers connection attempts, so a timer of an earlier attempt cannot fail a later one.
    private var attempt = 0

    public init(
        transport: any RadioTransport,
        clock: C,
        helloTimeout: Duration = defaultHelloTimeout,
        rxAudio: (any RXAudioSink)? = nil,
        microphone: (any AudioInput)? = nil
    ) {
        self.transport = transport
        self.clock = clock
        self.helloTimeout = helloTimeout
        self.rxAudio = rxAudio
        self.microphone = microphone
        snapshot = RadioSnapshot(status: .disconnected, desired: DesiredStateController().desired, isInSync: false)
        (snapshots, snapshotContinuation) = AsyncStream.makeStream()
        (frames, outbox) = AsyncStream.makeStream()
    }

    deinit {
        tasks.forEach { $0.cancel() }
        helloTimer?.cancel()
        capture?.cancel()
        runawayTimer?.cancel()
        scanTimer?.cancel()
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
        rxAudio?.reset()
        endTransmission()
        endScan()
        desiredState.setPTT(false)
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
        stopScan()
        activeMemoryId = memoryId
        let band = TXBand.default(for: firmware.moduleType)
        update { state in
            state.setRxFrequency(rx)
            state.setTxFrequency(tx)
            state.setMemoryId(memoryId)
            state.setTXAllowed(band.allows(tx, bandwidth: state.desired.bandwidth))
        }
    }

    /// `RadioAudioService.tuneToMemory`: RX and TX (with the offset) are made safe instead of refused. Ends a scan.
    public func tune(to memory: ChannelMemory) throws(RadioError) {
        guard snapshot.status == .ready, let firmware = desiredState.firmware else { throw .notReady }
        stopScan()
        update(tuning(to: memory, firmware: firmware))
    }

    /// The changes of `tuneToMemory`; `squelch` replaces the squelch while scanning.
    private func tuning(
        to memory: ChannelMemory,
        firmware: FirmwareVersion,
        squelch: UInt8? = nil
    ) -> @Sendable (inout DesiredStateController) -> Void {
        activeMemoryId = memory.id
        let range = firmware.minRadioFreq...firmware.maxRadioFreq
        let rx = HamFrequency.safe(memory.frequency, in: range)
        let tx = memory.txFrequency(in: range)
        let txTone = CTCSS.index(of: memory.txTone)
        let rxTone = CTCSS.index(of: memory.rxTone)
        let band = TXBand.default(for: firmware.moduleType)
        return { state in
            if let squelch {
                state.setSquelch(squelch)
            }
            state.setMemoryId(memory.id)
            state.setTxFrequency(tx)
            state.setRxFrequency(rx)
            state.setTxTone(txTone)
            state.setRxTone(rxTone)
            state.setTXAllowed(band.allows(tx, bandwidth: state.desired.bandwidth))
        }
    }

    // MARK: Scan

    /// `RadioAudioService.setScanning(true)`: tunes through `memories` (skipping marked ones and those outside the
    /// module range), moving on when the squelch stays closed for `scanAdvanceDelay`.
    public func startScan(_ memories: [ChannelMemory]) throws(RadioError) {
        guard snapshot.status == .ready else { throw .notReady }
        if scanList == nil {
            scanBaseSquelch = desiredState.desired.squelch
        }
        scanList = memories
        nextScan()
        publish(snapshot.status)
    }

    /// `RadioAudioService.setScanning(false)`: the squelch from before the scan returns.
    public func stopScan() {
        guard scanList != nil else { return }
        endScan()
        let squelch = scanBaseSquelch
        update { $0.setSquelch(squelch) }
    }

    private func endScan() {
        scanList = nil
        cancelScanTimer()
    }

    private func nextScan() {
        cancelScanTimer()
        guard let memories = scanList, !memories.isEmpty, let firmware = desiredState.firmware else { return }
        let range = firmware.minRadioFreq...firmware.maxRadioFreq
        let current = memories.firstIndex { $0.id == activeMemoryId } ?? -1
        let candidates = (1...memories.count).map { memories[(current + $0) % memories.count] }
        guard let next = candidates.first(where: { !$0.skipDuringScan && range.contains($0.frequency) }) else { return }
        let squelch = scanBaseSquelch > 0 ? scanBaseSquelch : Self.defaultScanSquelch
        update(tuning(to: next, firmware: firmware, squelch: squelch))
    }

    /// `checkScanDueToSquelch` on every device state.
    private func checkScan() {
        guard scanList != nil, let radio = desiredState.deviceState?.radio,
            radio.memoryId == activeMemoryId, radio.flags.contains(.squelched)
        else { return cancelScanTimer() }
        if scanTimer != nil, scanTimerMemory == activeMemoryId {
            return  // already waiting for this memory
        }
        cancelScanTimer()
        scanTimerMemory = activeMemoryId
        let generation = scanTimerGeneration
        let clock = clock
        scanTimer = Task { [weak self] in
            try? await clock.sleep(for: Self.scanAdvanceDelay)
            await self?.scanTimerFired(generation: generation)
        }
    }

    /// The squelch stayed closed on the same memory: move on.
    private func scanTimerFired(generation: Int) {
        guard generation == scanTimerGeneration else { return }
        scanTimer = nil
        guard let radio = desiredState.deviceState?.radio,
            radio.memoryId == activeMemoryId, radio.flags.contains(.squelched)
        else { return }
        nextScan()
    }

    private func cancelScanTimer() {
        scanTimerGeneration += 1
        scanTimer?.cancel()
        scanTimer = nil
        scanTimerMemory = -1
    }

    public func setMicGain(_ gain: MicGain) {
        txEncoder.gain = gain
    }

    // MARK: Transmit

    /// `RadioAudioService.startPtt`: keys the radio and sends the microphone as TX audio until `stopTransmitting()`,
    /// the device releases PTT (TX watchdog) or `runawayTXTimeout` passes.
    public func startTransmitting() async throws(RadioError) {
        guard snapshot.status == .ready else { throw .notReady }
        guard !isCapturing else { return }
        guard desiredState.desired.flags.contains(.txAllowed) else { throw .transmitNotAllowed }
        guard let microphone else { throw .microphoneUnavailable }
        stopScan()
        transmission += 1
        let current = transmission
        isCapturing = true
        let samples: AsyncStream<[Int16]>
        do {
            samples = try await microphone.start()
        } catch {
            isCapturing = false
            throw .microphoneUnavailable
        }
        guard current == transmission else { return microphone.stop() }  // ended while the microphone started
        txEncoder.reset()
        rxAudio?.reset()
        update { $0.setPTT(true) }
        capture = Task { [weak self] in
            for await chunk in samples {
                await self?.send(chunk, transmission: current)
            }
        }
        let clock = clock
        runawayTimer = Task { [weak self] in
            try? await clock.sleep(for: Self.runawayTXTimeout)
            await self?.runawayTimedOut(transmission: current)
        }
    }

    /// `RadioAudioService.endPtt`.
    public func stopTransmitting() {
        guard isCapturing else { return }
        endTransmission()
        update { $0.setPTT(false) }
    }

    private func send(_ chunk: [Int16], transmission sending: Int) {
        guard sending == transmission, isCapturing else { return }
        for block in txEncoder.encode(chunk) {
            outbox.yield(FrameEncoder.txAudio(block))
        }
    }

    private func runawayTimedOut(transmission timedOut: Int) {
        guard timedOut == transmission else { return }
        stopTransmitting()
    }

    /// Stops the microphone and timer; the RX audio fades in again, as on Android.
    private func endTransmission() {
        guard isCapturing else { return }
        transmission += 1
        isCapturing = false
        capture?.cancel()
        runawayTimer?.cancel()
        microphone?.stop()
        rxAudio?.reset()
    }

    /// Applies several changes as one desired state, e.g. `update { $0.setSquelch(4) }`.
    public func update(_ changes: @Sendable (inout DesiredStateController) -> Void) {
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
                    applyTXRule()
                    flush()
                    checkScan()
                }
            case .command(.rxAudio, let payload) where snapshot.status == .ready:
                rxAudio?.receive(block: payload)
            case .command(.windowUpdate, let payload):
                if let update = try? WindowUpdate(decoding: payload) {
                    await window.enlarge(by: Int(update.size))
                }
            default:
                break  // digital voice, AX.25 and debug output come with later milestones
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

    /// `updateTxAllowed` on every in-sync state: the TX frequency decides whether PTT is allowed.
    private func applyTXRule() {
        let desired = desiredState.desired
        guard desiredState.isAppliedStateInSync, desired.freqTx > 0, let firmware = desiredState.firmware else {
            return
        }
        let allowed = TXBand.default(for: firmware.moduleType).allows(desired.freqTx, bandwidth: desired.bandwidth)
        desiredState.setTXAllowed(allowed)
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
        if isCapturing, !desiredState.desired.flags.contains(.pttRequested) {
            endTransmission()  // the device released PTT
        }
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
        rxAudio?.reset()
        endTransmission()
        endScan()
        desiredState.setPTT(false)
        desiredState.detach()
        publish(.failed(failure))
    }

    private func publish(_ status: RadioStatus) {
        let next = RadioSnapshot(
            status: status,
            firmware: desiredState.firmware,
            deviceState: desiredState.deviceState,
            desired: desiredState.desired,
            isInSync: desiredState.isAppliedStateInSync,
            isScanning: scanList != nil,
            revision: snapshot.revision
        )
        guard next != snapshot else { return }
        snapshot = next
        snapshot.revision += 1
        snapshotContinuation.yield(snapshot)
    }
}

extension RadioController where C == ContinuousClock {
    public init(
        transport: any RadioTransport,
        helloTimeout: Duration = defaultHelloTimeout,
        rxAudio: (any RXAudioSink)? = nil,
        microphone: (any AudioInput)? = nil
    ) {
        self.init(
            transport: transport,
            clock: ContinuousClock(),
            helloTimeout: helloTimeout,
            rxAudio: rxAudio,
            microphone: microphone
        )
    }
}
