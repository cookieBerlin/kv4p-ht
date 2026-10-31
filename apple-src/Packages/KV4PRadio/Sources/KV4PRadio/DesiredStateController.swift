import KV4PProtocol

/// The host side of the desired/applied radio state, with the rules of the Android `RadioModuleController`
/// (pinned by `desired-state.json`).
///
/// Setters change the desired state; while attached and ready, every change is queued with the next sequence
/// number and taken with `takeOutgoing()`. Device states confirm, resynchronise or trigger a resend (at most three
/// times).
public struct DesiredStateController: Sendable {
    static let maxRetries = 3
    /// Flags compared between the desired and the reported state.
    static let comparedFlags = StateFlags.globalScope.union(.sessionScope)
    static let defaultFlags: StateFlags = [.highPower, .rssiEnabled, .enableStatusReports]
    static let defaultState = HostDesiredState(memoryId: -1, flags: defaultFlags, bandwidth: 1)

    public private(set) var desired = Self.defaultState
    public private(set) var isAppliedStateInSync = false
    /// The latest state reported by the device.
    public private(set) var deviceState: DeviceState?
    public private(set) var firmware: FirmwareVersion?

    private var attached = false
    private var ready = false
    private var lastSent: HostDesiredState?
    private var updateDepth = 0
    private var retries = 0
    private var outgoing: [HostDesiredState] = []

    public init() {}

    /// The states to send, in order, since the last call.
    public mutating func takeOutgoing() -> [HostDesiredState] {
        defer { outgoing = [] }
        return outgoing
    }

    // MARK: Session

    /// A transport was attached; nothing is sent until `markReady()`.
    public mutating func attach() {
        attached = true
        ready = false
        lastSent = desired
        retries = 0
    }

    public mutating func detach() {
        attached = false
        ready = false
        lastSent = nil
        deviceState = nil
        firmware = nil
        isAppliedStateInSync = false
        retries = 0
    }

    /// The handshake completed; pending changes are sent.
    public mutating func markReady() {
        ready = true
        sendIfChanged()
    }

    /// Adopts the state of `HELLO` as the desired state.
    public mutating func seed(_ state: DeviceState) {
        deviceState = state
        desired = Self.desired(from: state)
        var assumedSent = desired
        assumedSent.flags.remove(.enableStatusReports)
        lastSent = assumedSent
        isAppliedStateInSync = Self.isInSync(state, with: assumedSent)
        retries = 0
    }

    public mutating func seed(_ version: FirmwareVersion) {
        firmware = version
    }

    /// A `DEVICE_STATE` report. A newer device sequence (e.g. the TX watchdog released PTT) is adopted, keeping the
    /// session flags.
    public mutating func update(_ state: DeviceState) {
        deviceState = state
        if state.radio.sequence > desired.sequence {
            let hadUnsentChange = lastSent.map { desired != $0 } ?? false
            var synced = Self.desired(from: state)
            synced.flags = synced.flags.subtracting(.sessionScope).union(desired.flags.intersection(.sessionScope))
            desired = synced
            if !hadUnsentChange, lastSent != nil {
                lastSent = desired
            }
        }
        isAppliedStateInSync = lastSent.map { Self.isInSync(state, with: $0) } ?? false
        if isAppliedStateInSync {
            retries = 0
        } else {
            retryIfNeeded()
        }
    }

    // MARK: Changes

    /// Batches changes until the matching `endUpdate()`.
    public mutating func beginUpdate() {
        updateDepth += 1
    }

    public mutating func endUpdate() {
        guard updateDepth > 0 else { return }
        updateDepth -= 1
        sendIfChanged()
    }

    /// `0x00` = 12.5 kHz, `0x01` = 25 kHz.
    public mutating func setBandwidth(_ bandwidth: UInt8) {
        updateRadioConfig { $0.bandwidth = bandwidth }
    }

    public mutating func setTxFrequency(_ frequency: Float) {
        updateRadioConfig { $0.freqTx = frequency }
    }

    public mutating func setRxFrequency(_ frequency: Float) {
        updateRadioConfig { $0.freqRx = frequency }
    }

    public mutating func setMemoryId(_ memoryId: Int32) {
        updateRadioConfig { $0.memoryId = memoryId }
    }

    public mutating func setTxTone(_ tone: UInt8) {
        updateRadioConfig { $0.ctcssTx = tone }
    }

    public mutating func setRxTone(_ tone: UInt8) {
        updateRadioConfig { $0.ctcssRx = tone }
    }

    public mutating func setSquelch(_ squelch: UInt8) {
        updateRadioConfig { $0.squelch = squelch }
    }

    public mutating func setFilters(pre: Bool, high: Bool, low: Bool) {
        updateDesired { state in
            state.flags.subtract(.filters)
            state.flags.formUnion(Self.flags([(.filterPre, pre), (.filterHigh, high), (.filterLow, low)]))
        }
    }

    public mutating func setPTT(_ requested: Bool) {
        setFlag(.pttRequested, requested)
    }

    public mutating func setHighPower(_ on: Bool) {
        setFlag(.highPower, on)
    }

    public mutating func setRSSI(_ on: Bool) {
        setFlag(.rssiEnabled, on)
    }

    public mutating func setTXAllowed(_ allowed: Bool) {
        setFlag(.txAllowed, allowed)
    }

    /// Ignored unless the firmware supports FreeDV 2400B.
    public mutating func setFreeDV(_ on: Bool) {
        setFlag(.freeDV2400B, on && supportsFreeDV)
    }

    public var supportsFreeDV: Bool { firmware?.features.contains(.freeDV2400B) ?? false }

    /// Stream RX audio and status reports to this session.
    public mutating func openAudio() {
        updateDesired { $0.flags.formUnion([.rxAudioOpen, .enableStatusReports]) }
    }

    public mutating func closeAudio() {
        stop()
    }

    /// Clears RX audio, PTT and status reports.
    public mutating func stop() {
        updateDesired { $0.flags.subtract([.rxAudioOpen, .pttRequested, .enableStatusReports]) }
    }

    // MARK: Rules

    private mutating func setFlag(_ flag: StateFlags, _ on: Bool) {
        updateDesired { state in
            if on {
                state.flags.insert(flag)
            } else {
                state.flags.remove(flag)
            }
        }
    }

    /// A real change of the radio configuration also marks it valid.
    private mutating func updateRadioConfig(_ change: (inout HostDesiredState) -> Void) {
        updateDesired { state in
            let before = state
            change(&state)
            if state != before {
                state.flags.insert(.radioConfigValid)
            }
        }
    }

    private mutating func updateDesired(_ change: (inout HostDesiredState) -> Void) {
        var next = desired
        change(&next)
        guard next != desired else { return }
        desired = next
        sendIfChanged()
    }

    private mutating func sendIfChanged() {
        guard updateDepth == 0, attached, ready, desired != lastSent else { return }
        desired.sequence &+= 1
        lastSent = desired
        retries = 0
        isAppliedStateInSync = false
        outgoing.append(desired)
    }

    private mutating func retryIfNeeded() {
        guard attached, ready, let lastSent, desired == lastSent, retries < Self.maxRetries else { return }
        retries += 1
        outgoing.append(lastSent)
    }

    private static func flags(_ choices: [(StateFlags, Bool)]) -> StateFlags {
        StateFlags(choices.filter(\.1).map(\.0))
    }

    /// The desired state that reproduces a reported one; without a radio configuration the defaults.
    static func desired(from state: DeviceState) -> HostDesiredState {
        guard state.hasRadioConfig else {
            var defaults = defaultState
            defaults.sequence = state.radio.sequence
            return defaults
        }
        var desired = state.radio
        desired.flags = state.radio.flags.intersection(comparedFlags).subtracting([.pttRequested, .rxAudioOpen])
            .union(.enableStatusReports)
        return desired
    }

    static func isInSync(_ state: DeviceState, with desired: HostDesiredState) -> Bool {
        guard state.lastError == 0, state.radio.sequence == desired.sequence,
            state.radio.flags.intersection(comparedFlags) == desired.flags.intersection(comparedFlags)
        else { return false }
        guard desired.flags.contains(.radioConfigValid) else { return true }
        var config = state.radio
        config.flags = desired.flags
        return config == desired
    }
}
