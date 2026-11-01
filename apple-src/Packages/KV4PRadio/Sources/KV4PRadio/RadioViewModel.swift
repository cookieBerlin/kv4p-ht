import Foundation
import KV4PAPRS
import KV4PAudio
import KV4PPersistence
import KV4PProtocol
import KV4PTransport
import Observation

/// What the view model needs from `RadioController`, independent of its clock.
public protocol RadioControlling: Actor {
    nonisolated var snapshots: AsyncStream<RadioSnapshot> { get }
    nonisolated var receivedFrames: AsyncStream<[UInt8]> { get }
    func connect() async
    func disconnect() async
    func tune(rx: Float, tx: Float, memoryId: Int32) throws(RadioError)
    func update(_ changes: @Sendable (inout DesiredStateController) -> Void)
    var snapshot: RadioSnapshot { get }
    func setMicGain(_ gain: MicGain)
    func setFreeDV(_ on: Bool)
    func startTransmitting() async throws(RadioError)
    func stopTransmitting()
    func tune(to memory: ChannelMemory) throws(RadioError)
    func transmitAX25(_ frame: [UInt8], frequency: Float) throws(RadioError)
    func startScan(_ memories: [ChannelMemory]) throws(RadioError)
    func stopScan()
}

extension RadioController: RadioControlling {}

/// Pre-emphasis and the high- and low-pass audio filters of the SA818.
public struct AudioFilters: Equatable, Sendable {
    public var preEmphasis: Bool
    public var highPass: Bool
    public var lowPass: Bool

    public init(preEmphasis: Bool, highPass: Bool, lowPass: Bool) {
        self.preEmphasis = preEmphasis
        self.highPass = highPass
        self.lowPass = lowPass
    }
}

/// State and actions of the radio screen; the SwiftUI views only bind to it.
@MainActor
@Observable
public final class RadioViewModel {
    public enum Connection: Hashable, Sendable, Identifiable {
        case bluetooth
        /// A USB serial device path.
        case serial(String)
        case simulator

        public var id: String { label }

        public var label: String {
            switch self {
            case .bluetooth: "Bluetooth"
            case .serial(let path): "USB " + String(path.reversed().prefix { $0 != "/" }.reversed())
            case .simulator: "Simulator"
            }
        }
    }

    public private(set) var connections: [Connection] = []
    public var selectedConnection = Connection.bluetooth
    public private(set) var snapshot = RadioViewModel.disconnected
    /// The frequency field, in MHz.
    public var frequencyText = ""
    /// The last problem, in words for the user.
    public private(set) var message: String?

    private static let disconnected = RadioSnapshot(
        status: .disconnected,
        desired: DesiredStateController().desired,
        isInSync: false
    )
    /// Output gain of the RX audio, 0…1.
    public var volume: Float = 1 {
        didSet { rxAudio.volume = volume }
    }
    /// The simulator receives a signal (`canSimulateSignal`).
    public var isSignalSimulated = false {
        didSet {
            guard isSignalSimulated != oldValue, let simulateSignal else { return }
            let isOn = isSignalSimulated
            Task { await simulateSignal(isOn) }
        }
    }

    public var micGain = MicGain.none
    /// A PTT press starts transmitting, the next one ends it (Android "Sticky PTT").
    public var isStickyPTT = false

    /// All stored memories, in the order they were added.
    public private(set) var memories: [ChannelMemory] = []
    /// The group shown; `nil` for all memories.
    public var selectedGroup: String?

    /// APRS packets heard on air, newest first.
    public private(set) var aprsEvents: [APRSEvent] = []

    let rxAudio = RXAudioPlayer()
    /// The station's callsign for APRS, normalised; empty disables sending. Kept apart from `aprs`, which is still
    /// being changed when its callbacks read the callsign.
    public var callsign = "" {
        didSet {
            aprs.callsign = callsign
            if callsign != aprs.callsign {
                callsign = aprs.callsign
            }
            updateInternet()
        }
    }
    /// iGate: pass received RF packets and our own packets to APRS-IS.
    public var isIGateEnabled = false {
        didSet {
            aprs.isIGateEnabled = isIGateEnabled
            updateInternet()
        }
    }
    /// Show APRS-IS packets near our position in the feed.
    public var isInternetFeedEnabled = false {
        didSet {
            internetLocation = nil
            updateInternet()
            if isInternetFeedEnabled, let location {
                Task { await locateInternetFilter(with: location) }
            }
        }
    }
    /// An APRS-IS connection is available.
    public var canUseInternet: Bool { internet != nil }
    /// Logged in to APRS-IS.
    public private(set) var isInternetConnected = false

    /// Send a position beacon now and every five minutes (`AprsBeaconSchedule`).
    public var isBeaconEnabled = false {
        didSet {
            if isBeaconEnabled != oldValue {
                nextBeaconAtMs = 0
            }
        }
    }
    public var beaconSymbol = APRSSymbol.phone
    /// Round the position to 0.01° (about 1 km), Android's approximate accuracy.
    public var isBeaconApproximate = false
    /// Repeat packets for WIDE1-1 and our callsign.
    public var isDigipeatingEnabled: Bool {
        get { aprs.isDigipeatingEnabled }
        set { aprs.isDigipeatingEnabled = newValue }
    }
    /// A location is available for beacons.
    public var canBeacon: Bool { location != nil }

    static let beaconIntervalMs: Int64 = 5 * 60_000
    private var nextBeaconAtMs: Int64 = 0
    private let location: (any LocationProvider)?
    private let internet: (any APRSInternetLink)?
    private var internetLocation: GeoPoint?
    private var internetObservers: [Task<Void, Never>] = []
    private var aprs: APRSController
    private var packetObserver: Task<Void, Never>?
    private var aprsTicker: Task<Void, Never>?
    private let aprsTickInterval: Duration
    private let now: () -> Int64
    private let makeController: (Connection, any RXAudioSink) -> any RadioControlling
    private let serialDevices: () -> [String]
    private let audioOutput: (any AudioOutput)?
    private let simulateSignal: (@Sendable (Bool) async -> Void)?
    private let repository: (any MemoryRepository)?
    private var controller: (any RadioControlling)?
    private var connection: Connection?
    private var observer: Task<Void, Never>?
    /// The frequency shown when the field is reset.
    private var frequency: Float?

    /// `makeController` connects the RX audio of the radio to the given sink; `simulateSignal` starts or ends a
    /// carrier on the simulator.
    public init(
        makeController: @escaping (Connection, any RXAudioSink) -> any RadioControlling,
        serialDevices: @escaping () -> [String],
        audioOutput: (any AudioOutput)? = nil,
        simulateSignal: (@Sendable (Bool) async -> Void)? = nil,
        memories: (any MemoryRepository)? = nil,
        location: (any LocationProvider)? = nil,
        internet: (any APRSInternetLink)? = nil,
        now: @escaping () -> Int64 = RadioViewModel.systemTimeMs,
        aprsTickInterval: Duration = .milliseconds(500)
    ) {
        repository = memories
        self.location = location
        self.internet = internet
        self.now = now
        self.aprsTickInterval = aprsTickInterval
        var aprs = APRSController(startMs: now())
        aprs.txDestination = Self.aprsDestination
        aprs.txPath = ["WIDE1-1", "WIDE2-1"].compactMap(AX25Address.init)
        self.aprs = aprs
        self.makeController = makeController
        self.serialDevices = serialDevices
        self.audioOutput = audioOutput
        self.simulateSignal = simulateSignal
        refreshConnections()
        observeInternet()
    }

    /// Bluetooth, the USB serial devices present, and the built-in simulator.
    public func refreshConnections() {
        connections = [.bluetooth] + serialDevices().map(Connection.serial) + [.simulator]
    }

    public var isReady: Bool { snapshot.status == .ready }

    public var canConnect: Bool {
        switch snapshot.status {
        case .disconnected, .failed: true
        default: false
        }
    }

    public var statusText: String { Self.statusText(for: snapshot) }

    /// E.g. `Firmware 17 · VHF 134–174 MHz`.
    public var firmwareText: String? {
        snapshot.firmware.map { firmware in
            let band = firmware.moduleType == .sa818UHF ? "UHF" : "VHF"
            return
                "Firmware \(firmware.version) · \(band) \(Int(firmware.minRadioFreq))–\(Int(firmware.maxRadioFreq)) MHz"
        }
    }

    public var sMeter: Int { snapshot.sMeter }

    public var sMeterText: String { Self.sMeterText(for: sMeter) }

    /// The squelch is open: a signal is received and played.
    public var isReceiving: Bool {
        guard isReady, let flags = snapshot.deviceState?.radio.flags else { return false }
        return !flags.contains(.squelched)
    }

    /// PTT is pressed (the radio may not have keyed up yet).
    public var isTransmitting: Bool { snapshot.isTransmitting }

    /// The radio reports that it transmits.
    public var isOnAir: Bool { isReady && snapshot.deviceState?.radio.flags.contains(.txActive) == true }

    /// The TX frequency is inside the ham band.
    public var canTransmit: Bool { isReady && snapshot.desired.flags.contains(.txAllowed) }

    public var canSimulateSignal: Bool { isReady && connection == .simulator && simulateSignal != nil }

    // MARK: Connection

    public func connect() async {
        await disconnect()
        let controller = makeController(selectedConnection, rxAudio)
        self.controller = controller
        connection = selectedConnection
        message = nil
        frequency = nil
        do {
            try audioOutput?.start(rxAudio)
        } catch {
            message = "The audio output cannot be started."
        }
        let snapshots = controller.snapshots
        observer = Task { [weak self] in
            for await snapshot in snapshots {
                self?.show(snapshot)
            }
        }
        let frames = controller.receivedFrames
        packetObserver = Task { [weak self] in
            for await frame in frames {
                self?.receive(frame)
            }
        }
        let interval = aprsTickInterval
        aprsTicker = Task { [weak self] in
            while (try? await Task.sleep(for: interval)) != nil {
                self?.tickAPRS()
            }
        }
        await controller.connect()
    }

    public func disconnect() async {
        observer?.cancel()
        observer = nil
        packetObserver?.cancel()
        packetObserver = nil
        aprsTicker?.cancel()
        aprsTicker = nil
        await controller?.disconnect()
        audioOutput?.stop()
        controller = nil
        connection = nil
        isSignalSimulated = false
        snapshot = Self.disconnected
    }

    private func show(_ snapshot: RadioSnapshot) {
        guard snapshot.revision >= self.snapshot.revision else { return }  // already showing a newer one
        self.snapshot = snapshot
        if case .failed(let failure) = snapshot.status {
            message = Self.message(for: failure)
        }
        if snapshot.status == .ready, let reported = snapshot.deviceState?.radio.freqRx, reported != frequency {
            frequency = reported
            frequencyText = HamFrequency.format(reported)
        }
    }

    // MARK: APRS

    /// Milliseconds since 1970, the time base of APRS events.
    public nonisolated static let systemTimeMs: @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }

    /// Frames that are not APRS are ignored, as on Android.
    private func receive(_ frame: [UInt8]) {
        guard let packet = try? APRSParser.parse(ax25: frame) else { return }
        aprs.receive(
            packet,
            frame: frame,
            frequencyHz: rxFrequencyHz,
            atMs: now(),
            transmit: transmitAPRS,
            gate: gateAPRS
        )
        showAPRS()
    }

    /// The AX.25 destination of the Android app (`APRS_TOCALL`).
    static let aprsDestination = "APKVPA"

    /// The frequency packets are received on, in Hz.
    private var rxFrequencyHz: Int64? {
        snapshot.deviceState.map { Self.hertz($0.radio.freqRx) }
    }

    /// `AprsRfFrequencyPolicy.toHz`: via the decimal text of the `Float`, so 144.8 is 144 800 000 Hz.
    static func hertz(_ megahertz: Float) -> Int64 {
        Int64((strtod(megahertz.description, nil) * 1_000_000).rounded())
    }

    /// `sendChatMessage`: `|`, `~` and `{` become spaces; without a recipient the message is the bulletin BLN1CQ.
    public func sendAPRSMessage(to recipient: String, text: String) {
        guard !callsign.isEmpty else {
            message = "Set your callsign to send APRS messages."
            return
        }
        let cleaned = String(text.map { "|~{".contains($0) ? " " : $0 })
        let to = recipient.trimmingCharacters(in: .whitespaces).isEmpty ? "BLN1CQ" : recipient
        let frequency = Self.hertz(snapshot.desired.freqTx)
        let posted = aprs.post(
            to: to,
            text: cleaned,
            frequencyHz: frequency,
            atMs: now(),
            transmit: transmitAPRS,
            gate: gateAPRS
        )
        if !posted {
            message = "The APRS message was not accepted for transmission."
        }
        showAPRS()
    }

    private func tickAPRS() {
        isInternetConnected = internet?.isLoggedIn ?? false
        let time = now()
        aprs.tick(atMs: time, transmit: transmitAPRS)
        if isBeaconEnabled, time >= nextBeaconAtMs, let location {
            nextBeaconAtMs = time + Self.beaconIntervalMs
            Task { await beacon(from: location) }
        }
        showAPRS()
    }

    /// `sendPositionBeacon`: compressed, messaging capable, primary table, on the current TX frequency.
    private func beacon(from location: any LocationProvider) async {
        guard let point = await location.currentLocation() else {
            message = "Your location is unknown."
            return
        }
        let round = { (value: Double) in self.isBeaconApproximate ? (value * 100 + 0.5).rounded(.down) / 100 : value }
        let beacon = APRSBeacon(
            latitude: round(point.latitude),
            longitude: round(point.longitude),
            symbolTable: "/",
            symbolCode: beaconSymbol.code
        )
        _ = aprs.submitBeacon(beacon, atMs: now(), transmit: transmitAPRS, gate: gateAPRS)
        showAPRS()
    }

    private func showAPRS() {
        aprsEvents = aprs.events.sorted { $0.lastSeenMs > $1.lastSeenMs }
    }

    /// `ServiceAprsCallbacks.submitAprsIs`.
    private func gateAPRS(_ request: APRSInternetRequest) -> Bool {
        guard let internet else { return false }
        return internet.send(request, as: callsign)
    }

    /// `updateAprsIsConnection`: connected while the iGate or the feed is on; sending only for the iGate.
    private func updateInternet() {
        let active = isIGateEnabled || isInternetFeedEnabled
        internet?.update(
            APRSISSettings(
                isEnabled: active,
                isReceiveEnabled: isInternetFeedEnabled,
                isTransmitEnabled: isIGateEnabled,
                callsign: callsign,
                latitude: internetLocation?.latitude,
                longitude: internetLocation?.longitude
            )
        )
        isInternetConnected = internet?.isLoggedIn ?? false
    }

    /// `refreshAprsIsFilterLocation`: the feed shows packets around our position.
    private func locateInternetFilter(with location: any LocationProvider) async {
        guard let point = await location.currentLocation(), isInternetFeedEnabled else { return }
        internetLocation = point
        updateInternet()
    }

    private func observeInternet() {
        guard let internet else { return }
        let received = internet.received
        let delivered = internet.delivered
        internetObservers = [
            Task { [weak self] in
                for await line in received {
                    self?.receiveInternet(line)
                }
            },
            Task { [weak self] in
                for await request in delivered {
                    self?.confirmInternet(request)
                }
            },
        ]
    }

    private func receiveInternet(_ line: String) {
        aprs.receive(internetLine: line, atMs: now())
        showAPRS()
    }

    private func confirmInternet(_ request: APRSInternetRequest) {
        aprs.recordInternetTransmission(request, atMs: now())
        showAPRS()
    }

    /// `ServiceAprsCallbacks.submitRf` with `AprsRfFrequencyPolicy`: only while receiving; a reliable message stays on
    /// its frequency, everything else goes out on the requested or current TX frequency, within the ham band.
    private func transmitAPRS(_ request: APRSTransmitRequest) -> APRSTransmitOutcome {
        guard isReady, !isTransmitting, !isScanning, let controller, let firmware = snapshot.firmware else {
            return .later
        }
        let selected = Self.hertz(snapshot.desired.freqTx)
        let reliable = request.purpose == .outgoingMessage || request.purpose == .reliableMessageRetry
        if reliable, let requested = request.frequencyHz, requested != selected {
            return .never  // the app does not retune to the original frequency
        }
        let hertz: Int64
        switch (reliable, request.frequencyHz) {
        case (false, let requested?): hertz = requested
        default: hertz = selected
        }
        let megahertz = Float(Double(hertz) / 1_000_000)
        guard TXBand.default(for: firmware.moduleType).allows(megahertz, bandwidth: snapshot.desired.bandwidth),
            let frame = try? request.packet.ax25Frame()
        else { return .later }
        Task { try? await controller.transmitAX25(frame, frequency: megahertz) }
        return .accepted(frequencyHz: hertz, frame: frame)
    }

    // MARK: Transmit

    /// `MainActivity.handlePttPress`: starts transmitting, or with sticky PTT toggles.
    public func pressPTT() async {
        guard isReady, let controller else { return }
        if isStickyPTT, isTransmitting {
            await controller.stopTransmitting()
        } else {
            await controller.setMicGain(micGain)
            do {
                try await controller.startTransmitting()
            } catch {
                message = Self.message(for: error)
            }
        }
        show(await controller.snapshot)
    }

    /// `MainActivity.handlePttRelease`: ends the transmission unless PTT is sticky.
    public func releasePTT() async {
        guard !isStickyPTT, let controller else { return }
        await controller.stopTransmitting()
        show(await controller.snapshot)
    }

    // MARK: Memories

    public var groups: [String] { ChannelMemory.groups(in: memories) }

    public var visibleMemories: [ChannelMemory] {
        guard let selectedGroup else { return memories }
        return memories.filter { $0.group == selectedGroup }
    }

    /// The memory the radio is tuned to.
    public var activeMemoryId: Int32? {
        let id = snapshot.desired.memoryId
        return isReady && id >= 0 ? id : nil
    }

    public var isScanning: Bool { snapshot.isScanning }

    public func loadMemories() async {
        await store { repository in
            memories = try await repository.all()
        }
    }

    /// Adds a new memory (id 0) or replaces the one with the same id.
    public func save(_ memory: ChannelMemory) async {
        await store { repository in
            if memory.id == 0 {
                _ = try await repository.insert([memory])
            } else {
                try await repository.update(memory)
            }
            memories = try await repository.all()
        }
    }

    public func delete(_ memory: ChannelMemory) async {
        await store { repository in
            try await repository.delete(id: memory.id)
            memories = try await repository.all()
        }
    }

    public func tune(to memory: ChannelMemory) async {
        guard let controller else { return }
        try? await controller.tune(to: memory)
        show(await controller.snapshot)
    }

    /// Starts scanning the visible memories, or stops.
    public func toggleScan() async {
        guard let controller else { return }
        if isScanning {
            await controller.stopScan()
        } else {
            try? await controller.startScan(visibleMemories)
        }
        show(await controller.snapshot)
    }

    /// Adds the repeaters of a RepeaterBook CSV export that the radio can receive as memories of `group`.
    public func importRepeaterBook(_ csv: String, group: String) async {
        guard let firmware = snapshot.firmware else {
            message = "Connect the radio first, so that only repeaters it can receive are imported."
            return
        }
        let range = firmware.minRadioFreq...firmware.maxRadioFreq
        guard let imported = RepeaterBookImport.memories(fromCSV: csv, group: group, range: range) else {
            message = "This file is not a RepeaterBook CSV export."
            return
        }
        await store { repository in
            _ = try await repository.insert(imported)
            memories = try await repository.all()
            message = "Imported \(imported.count) repeater\(imported.count == 1 ? "" : "s")."
        }
    }

    private func store(_ change: (any MemoryRepository) async throws -> Void) async {
        guard let repository else { return }
        do {
            try await change(repository)
        } catch {
            message = "The memories could not be loaded or saved."
        }
    }

    // MARK: Settings

    /// Tunes RX and TX to the entered frequency, normalised and clamped like the Android app.
    public func applyFrequency() async {
        guard isReady, let controller, let firmware = snapshot.firmware, let current = frequency else { return }
        guard let entered = HamFrequency.safe(frequencyText, in: firmware.minRadioFreq...firmware.maxRadioFreq) else {
            message = "\"\(frequencyText)\" is not a frequency."
            frequencyText = HamFrequency.format(current)
            return
        }
        message = nil
        frequency = entered
        frequencyText = HamFrequency.format(entered)
        try? await controller.tune(rx: entered, tx: entered, memoryId: -1)
    }

    /// 25 kHz instead of 12.5 kHz.
    public var isWideBandwidth: Bool {
        get { snapshot.desired.bandwidth == 1 }
        set { update { $0.setBandwidth(newValue ? 1 : 0) } }
    }

    /// 0 (open) … 8.
    public var squelch: Int {
        get { Int(snapshot.desired.squelch) }
        set {
            let squelch = UInt8(clamping: newValue)
            update { $0.setSquelch(squelch) }
        }
    }

    public var isHighPower: Bool {
        get { snapshot.desired.flags.contains(.highPower) }
        set { update { $0.setHighPower(newValue) } }
    }

    /// The firmware offers FreeDV 2400B digital voice.
    public var supportsFreeDV: Bool { snapshot.supportsFreeDV }

    /// Voice mode: FreeDV 2400B instead of analog FM.
    public var isFreeDV: Bool {
        get { snapshot.isFreeDV }
        set {
            guard isReady, let controller else { return }
            Task { await controller.setFreeDV(newValue) }
        }
    }

    /// A label of `CTCSS.labels`.
    public var txTone: String {
        get { Self.label(snapshot.desired.ctcssTx) }
        set {
            let index = CTCSS.index(of: newValue)
            update { $0.setTxTone(index) }
        }
    }

    /// A label of `CTCSS.labels`.
    public var rxTone: String {
        get { Self.label(snapshot.desired.ctcssRx) }
        set {
            let index = CTCSS.index(of: newValue)
            update { $0.setRxTone(index) }
        }
    }

    public var filters: AudioFilters {
        get {
            let flags = snapshot.desired.flags
            return AudioFilters(
                preEmphasis: flags.contains(.filterPre),
                highPass: flags.contains(.filterHigh),
                lowPass: flags.contains(.filterLow)
            )
        }
        set { update { $0.setFilters(pre: newValue.preEmphasis, high: newValue.highPass, low: newValue.lowPass) } }
    }

    private func update(_ changes: @escaping @Sendable (inout DesiredStateController) -> Void) {
        guard isReady, let controller else { return }
        Task { await controller.update(changes) }
    }

    // MARK: Texts and rules

    static func statusText(for snapshot: RadioSnapshot) -> String {
        switch snapshot.status {
        case .disconnected: "Not connected"
        case .connecting: "Connecting…"
        case .waitingForHello: "Waiting for the radio…"
        case .ready: snapshot.isInSync ? "Connected" : "Connected, applying settings…"
        case .failed(let failure): message(for: failure)
        }
    }

    static func message(for failure: RadioFailure) -> String {
        switch failure {
        case .helloTimeout: "The radio did not answer. Check that it is on and has firmware 17 or later."
        case .invalidHello: "The firmware of the radio is too old. Update it to version 17 or later."
        case .firmwareTooOld(let version): "Firmware \(version) is too old. Update the radio to version 17 or later."
        case .radioModuleNotFound: "The SA818 radio module did not respond. Restart the radio."
        case .transport(let error): message(for: error)
        }
    }

    static func message(for error: RadioError) -> String {
        switch error {
        case .transmitNotAllowed: "Can't transmit outside the ham band."
        case .microphoneUnavailable:
            "The microphone is not available. Allow access in System Settings → Privacy & Security → Microphone."
        case .notReady, .frequencyOutOfRange: "The radio is not ready."
        case .busy: "The radio is busy transmitting or scanning."
        case .invalidPacket: "The packet cannot be sent."
        }
    }

    private static func message(for error: TransportError) -> String {
        switch error {
        case .bluetoothUnavailable(.unauthorized):
            "Bluetooth access is not allowed. Allow it in System Settings → Privacy & Security → Bluetooth."
        case .bluetoothUnavailable(.poweredOff): "Bluetooth is off."
        case .bluetoothUnavailable: "Bluetooth is not available."
        case .serviceNotFound: "This device is not a kv4p HT, or its firmware has no Bluetooth LE service."
        case .connectionLost: "The connection to the radio was lost."
        case .portUnavailable(let path, _): "\(path) cannot be opened."
        default: "The connection failed."
        }
    }

    /// `S0`…`S9`, then 20 dB steps (`S9+20`…`S9+60`), then `Overload` (`SMeter.overload`).
    static func sMeterText(for value: Int) -> String {
        switch value {
        case SMeter.overload: "Overload"
        case 10...: "S9+\((value - 9) * 20)"
        default: "S\(value)"
        }
    }

    private static func label(_ tone: UInt8) -> String {
        CTCSS.label(for: tone) ?? CTCSS.none
    }
}
