import KV4PAudio
import KV4PProtocol

/// A packet the device accepted for transmission.
public struct TransmittedPacket: Equatable, Sendable {
    /// AX.25 without FCS.
    public var packet: [UInt8]
    /// The channel of `HOST_TX_AX25`; `nil` for KISS DATA on the configured channel.
    public var channel: TXChannel?
}

/// In-process simulation of the device side of the protocol, deterministic and driven by explicit time
/// (ADR-0014 A). It reproduces firmware 17 for one session: `HELLO` on connect, desired-state handling,
/// status reports, `WINDOW_UPDATE` for every frame, the TX watchdog and runaway TX protection.
///
/// Every call takes the time since power-on and returns the bytes the device writes to the host. Times
/// must not decrease. Deadlines that pass between calls (status reports, watchdog) are processed in order.
///
/// RX audio follows `carrier`: without one the squelch is closed and the audio muted. In FreeDV 2400B mode the
/// carrier's voice frames replace the RX audio, and a signal without them keeps the squelch closed.
///
/// Not simulated yet: the squelch level, the FreeDV modem itself, the AX.25 TX scheduler (accepted
/// packets are recorded in `transmittedPackets`) and the physical PTT button.
public struct RadioSimulator: Sendable {
    public let scenario: Scenario
    public private(set) var now = Duration.zero
    public private(set) var isConnected = false
    /// The firmware retries an SA818 command forever; it neither reads nor writes any more.
    public private(set) var isStalled = false
    public private(set) var transmittedPackets: [TransmittedPacket] = []
    public private(set) var kissParameters: [KISS.Parameter: UInt8] = [:]
    public private(set) var carrier: Carrier?
    /// `HOST_TX_AUDIO` blocks accepted while transmitting, and the latest one.
    public private(set) var transmittedAudioBlocks = 0
    public private(set) var lastTransmittedAudio: [UInt8]?
    /// `HOST_TX_DIGITAL` frames accepted while transmitting in FreeDV mode, and the latest one.
    public private(set) var transmittedDigitalFrames = 0
    public private(set) var lastTransmittedDigital: [UInt8]?

    private var parser = HostFrameParser()
    private var desired: RadioState
    private var applied = RadioState()
    private var sessionFlags: StateFlags = []
    private var radioResponds: Bool
    private var radioConfigApplied = false
    private var filtersApplied = false
    private var mode = DeviceMode.stopped
    private var stateDirty = false
    private var lastReport = Duration.zero
    private var txStart = Duration.zero
    private var lastTXAudio = Duration.zero
    private var isStreamingAudio = false
    private var lastRXAudio = Duration.zero
    private var rxEncoder = ImaAdpcm.Encoder()
    /// Position in the tone, 0 ..< `KV4P.audioSampleRate`.
    private var toneIndex = 0
    /// The next of the carrier's voice frames.
    private var voiceFrameIndex = 0

    /// Boots the device at time zero.
    public init(scenario: Scenario = Scenario()) {
        self.scenario = scenario
        carrier = scenario.carrier
        desired = Self.bootState(scenario)
        applied.memoryId = desired.memoryId
        radioResponds = scenario.radioModuleStatus == .found
        if radioResponds {
            reconcile(sendReport: false)
        }
        radioResponds = radioResponds && !scenario.faults.radioModuleStopsResponding
    }

    /// The state the device would report now.
    public var deviceState: DeviceState {
        var radio = applied
        radio.sequence = desired.sequence
        radio.flags = desired.flags.union(sessionFlags)
        if !isSignalOpen {
            radio.flags.insert(.squelched)
        }
        if mode == .tx {
            radio.flags.insert(.txActive)
        }
        let rssi = radio.flags.contains(.rssiEnabled) ? carrier?.rssi ?? 0 : 0
        return DeviceState(radio: radio, radioModuleStatus: scenario.radioModuleStatus, mode: mode, latestRssi: rssi)
    }

    /// The transport connected (BLE: notify subscription); the device sends `HELLO`.
    public mutating func connect(at time: Duration) -> [UInt8] {
        step(to: time) { simulator in
            simulator.parser = HostFrameParser()
            simulator.isConnected = true
            let faults = simulator.scenario.faults
            return faults.omitsHello ? [] : faults.garbageBeforeHello + DeviceFrameEncoder.hello(simulator.hello)
        }
    }

    /// The transport disconnected; the session flags are cleared, a requested PTT stays until the watchdog fires.
    public mutating func disconnect(at time: Duration) -> [UInt8] {
        step(to: time) { simulator in
            simulator.parser = HostFrameParser()
            simulator.isConnected = false
            let hadSessionFlags = !simulator.sessionFlags.isEmpty
            simulator.sessionFlags = []
            if hadSessionFlags {
                simulator.reconcile()
            }
            return []
        }
    }

    /// Bytes written by the host.
    public mutating func receive(_ bytes: some Sequence<UInt8>, at time: Duration) -> [UInt8] {
        step(to: time) { simulator in
            var output: [UInt8] = []
            for frame in simulator.parser.process(bytes) {
                simulator.handle(frame.content)
                guard !simulator.isStalled else { break }
                if !simulator.scenario.faults.dropsWindowUpdates {
                    output += DeviceFrameEncoder.windowUpdate(WindowUpdate(size: UInt32(frame.encodedLength)))
                }
                output += simulator.loop()
            }
            return output
        }
    }

    /// Lets time pass without input.
    public mutating func advance(to time: Duration) -> [UInt8] {
        step(to: time) { _ in [] }
    }

    /// An AX.25 packet (without FCS) received on air.
    public mutating func hear(_ packet: [UInt8], at time: Duration) -> [UInt8] {
        inject(DeviceFrameEncoder.ax25(packet), at: time)
    }

    /// A signal starts (or, with `nil`, ends) on the receive frequency.
    public mutating func setCarrier(_ carrier: Carrier?, at time: Duration) -> [UInt8] {
        step(to: time) { simulator in
            if simulator.carrier != carrier {
                simulator.carrier = carrier
                simulator.stateDirty = true
            }
            return []
        }
    }

    /// Raw bytes written to a connected host, e.g. malformed frames.
    public mutating func inject(_ bytes: [UInt8], at time: Duration) -> [UInt8] {
        step(to: time) { simulator in simulator.isConnected ? bytes : [] }
    }

    // MARK: - Firmware main loop

    /// Processes the deadlines up to `time`, then `action`, then one main loop pass.
    private mutating func step(to time: Duration, _ action: (inout Self) -> [UInt8]) -> [UInt8] {
        precondition(time >= now)  // simulator time must not decrease
        guard !isStalled else { return [] }
        var output: [UInt8] = []
        while let deadline = nextDeadline(), deadline <= time {
            now = max(now, deadline)
            output += loop()
        }
        now = time
        output += action(&self)
        return isStalled ? output : output + loop()
    }

    private func nextDeadline() -> Duration? {
        var deadlines: [Duration] = []
        if sessionFlags.contains(.enableStatusReports) {
            deadlines.append(lastReport + Firmware.statusReportInterval)
        }
        if streamsAudio {
            deadlines.append(lastRXAudio + rxPeriod)
        }
        if mode == .tx {
            deadlines.append(lastTXAudio + Firmware.txAudioTimeout)
            deadlines.append(txStart + Firmware.runawayTX + .milliseconds(1))
        }
        return deadlines.min()
    }

    /// The part of the firmware `loop()` after the protocol parser: `txAudioLoop()`, `rxAudioLoop()`, then
    /// `deviceStateLoop()`.
    private mutating func loop() -> [UInt8] {
        txAudioLoop()
        return rxAudioLoop() + deviceStateLoop()
    }

    /// `sendAudio()` streams only to sessions with `RX_AUDIO_OPEN`, and not while transmitting.
    private var streamsAudio: Bool { isConnected && sessionFlags.contains(.rxAudioOpen) && mode != .tx }

    /// One block per `audioBlockPeriod`, counted from the moment streaming starts.
    private mutating func rxAudioLoop() -> [UInt8] {
        guard streamsAudio else {
            isStreamingAudio = false
            return []
        }
        if !isStreamingAudio {
            isStreamingAudio = true
            lastRXAudio = now
        }
        var output: [UInt8] = []
        while now - lastRXAudio >= rxPeriod {
            lastRXAudio += rxPeriod
            output += isFreeDV ? nextVoiceFrame() : DeviceFrameEncoder.rxAudio(rxEncoder.encodeBlock(nextRXSamples()))
        }
        return output
    }

    private var isFreeDV: Bool { desired.flags.contains(.freeDV2400B) }

    /// The squelch: any carrier opens it, in FreeDV mode only one with voice frames (`freeDvSquelch.open()`).
    private var isSignalOpen: Bool {
        guard let carrier else { return false }
        return !isFreeDV || !carrier.voiceFrames.isEmpty
    }

    /// An `RX_AUDIO` block, or in FreeDV mode one decoded frame.
    private var rxPeriod: Duration { isFreeDV ? Firmware.freeDVFramePeriod : Firmware.audioBlockPeriod }

    /// `sendDigitalFrame()`: only frames the modem decoded; nothing while squelched.
    private mutating func nextVoiceFrame() -> [UInt8] {
        guard isSignalOpen, let frames = carrier?.voiceFrames else { return [] }
        defer { voiceFrameIndex = (voiceFrameIndex + 1) % frames.count }
        return DeviceFrameEncoder.rxDigital(frames[voiceFrameIndex % frames.count])
    }

    /// The tone of the carrier; silence while squelched (`mute.setActive(squelched)`).
    private mutating func nextRXSamples() -> [Int16] {
        (0..<KV4P.audioBlockSamples).map { _ in
            defer { toneIndex = (toneIndex + 1) % KV4P.audioSampleRate }
            return carrier?.sample(toneIndex) ?? 0
        }
    }

    private mutating func txAudioLoop() {
        guard mode == .tx else { return }
        if desired.flags.contains(.pttRequested), now - lastTXAudio >= Firmware.txAudioTimeout {
            releaseHostPTT()
        } else if now - txStart > Firmware.runawayTX {
            releaseHostPTT()
        }
    }

    private mutating func deviceStateLoop() -> [UInt8] {
        guard sessionFlags.contains(.enableStatusReports) else { return [] }
        var output: [UInt8] = []
        if stateDirty {
            output = DeviceFrameEncoder.deviceState(deviceState)
            stateDirty = false
        }
        if now - lastReport >= Firmware.statusReportInterval {
            lastReport = now
            if output.isEmpty {
                output = DeviceFrameEncoder.deviceState(deviceState)
            }
        }
        return output
    }

    // MARK: - Commands

    private mutating func handle(_ frame: HostFrame?) {
        switch frame {
        case .ax25(let packet):
            if desired.flags.contains(.txAllowed) {
                transmittedPackets.append(TransmittedPacket(packet: packet, channel: nil))
            }
        case .kissParameter(let parameter, let value):
            kissParameters[parameter] = value
        case .command(.desiredState, let payload):
            if let state = try? RadioState(decoding: payload) {
                apply(state)
            }
        case .command(.txAudio, let payload):
            if mode == .tx, !desired.flags.contains(.freeDV2400B), !payload.isEmpty {
                lastTXAudio = now
                transmittedAudioBlocks += 1
                lastTransmittedAudio = payload
            }
        case .command(.txAX25, let payload):
            transmit(payload)
        case .command(.txDigital, let payload):
            // `processTxDigital`: one Codec2 frame, which also feeds the TX watchdog.
            if mode == .tx, isFreeDV, payload.count == 7 {
                lastTXAudio = now
                transmittedDigitalFrames += 1
                lastTransmittedDigital = payload
            }
        case nil:
            break
        }
    }

    /// `COMMAND_HOST_DESIRED_STATE`: session flags always apply, the global state only with a newer sequence.
    private mutating func apply(_ incoming: RadioState) {
        let oldSessionFlags = sessionFlags
        sessionFlags = incoming.flags.intersection(.sessionScope)
        let globalStateChanged = incoming.sequence > desired.sequence
        if globalStateChanged {
            desired = incoming
            desired.flags.formIntersection(.globalScope)
        }
        if globalStateChanged || sessionFlags != oldSessionFlags {
            reconcile()
        }
    }

    /// `COMMAND_HOST_TX_AX25`: the header selects the channel; unlike KISS DATA it does not need `TX_ALLOWED`.
    private mutating func transmit(_ payload: [UInt8]) {
        let packet = Array(payload.dropFirst(TXChannel.byteCount))
        guard !packet.isEmpty, packet.count <= KV4P.ax25MaxDataLength,
            let channel = try? TXChannel(decoding: Array(payload.prefix(TXChannel.byteCount))),
            scenario.frequencyRange.contains(channel.freqTx)
        else { return }
        transmittedPackets.append(TransmittedPacket(packet: packet, channel: channel))
    }

    // MARK: - Radio

    /// `reconcileDesiredState()`. Every SA818 command stalls the device if the module does not respond.
    private mutating func reconcile(sendReport: Bool = true) {
        let filters = desired.flags.intersection(.filters)
        if !filtersApplied || filters != applied.flags.intersection(.filters) {
            guard radioResponds else { return stall() }
            applied.flags = applied.flags.subtracting(.filters).union(filters)
            filtersApplied = true
        }
        if desired.flags.contains(.radioConfigValid), radioConfigChanged {
            guard radioResponds else { return stall() }
            let flags = applied.flags
            applied = desired
            applied.flags = flags.union(.radioConfigValid)
            radioConfigApplied = true
        }
        setMode(desired.flags.isSuperset(of: [.pttRequested, .txAllowed]) ? .tx : idleMode)
        if sendReport {
            stateDirty = true
        }
    }

    private var radioConfigChanged: Bool {
        var config = applied
        config.sequence = desired.sequence
        config.flags = desired.flags
        return !radioConfigApplied || config != desired
    }

    private mutating func stall() {
        isStalled = true
    }

    private var idleMode: DeviceMode { sessionFlags.contains(.rxAudioOpen) ? .rx : .stopped }

    private mutating func setMode(_ newMode: DeviceMode) {
        guard newMode != mode else { return }
        mode = newMode
        stateDirty = true
        if newMode == .tx {
            txStart = now
            lastTXAudio = now
        }
    }

    /// `releaseHostPtt()`: the device clears PTT itself and bumps the sequence so the host resyncs.
    private mutating func releaseHostPTT() {
        desired.flags.remove(.pttRequested)
        desired.sequence &+= 1
        setMode(idleMode)
    }

    private var hello: Hello {
        let range = scenario.frequencyRange
        let version = FirmwareVersion(
            version: scenario.firmwareVersion,
            radioModuleStatus: scenario.radioModuleStatus,
            windowSize: scenario.windowSize,
            moduleType: scenario.moduleType,
            minRadioFreq: range.lowerBound,
            maxRadioFreq: range.upperBound,
            features: scenario.features
        )
        return Hello(version: version, deviceState: deviceState)
    }

    /// `loadPersistedRadioState()`.
    private static func bootState(_ scenario: Scenario) -> RadioState {
        let frequency = scenario.defaultFrequency
        var state =
            scenario.storedState
            ?? RadioState(
                memoryId: -1,
                flags: [.highPower, .rssiEnabled],
                bandwidth: 1,
                freqTx: frequency,
                freqRx: frequency
            )
        state.sequence = 0
        state.flags = state.flags.intersection(Firmware.persistedFlags).union(.radioConfigValid)
        let range = scenario.frequencyRange
        if !range.contains(state.freqTx) || !range.contains(state.freqRx) {
            state.freqTx = min(max(state.freqTx, range.lowerBound), range.upperBound)
            state.freqRx = min(max(state.freqRx, range.lowerBound), range.upperBound)
            state.memoryId = -1
        }
        return state
    }
}
