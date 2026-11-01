import Foundation
import KV4PAudio
import KV4PProtocol
import KV4PTransport
import Observation

/// What the view model needs from `RadioController`, independent of its clock.
public protocol RadioControlling: Actor {
    nonisolated var snapshots: AsyncStream<RadioSnapshot> { get }
    func connect() async
    func disconnect() async
    func tune(rx: Float, tx: Float, memoryId: Int32) throws(RadioError)
    func update(_ changes: @Sendable (inout DesiredStateController) -> Void)
    var snapshot: RadioSnapshot { get }
    func setMicGain(_ gain: MicGain)
    func startTransmitting() async throws(RadioError)
    func stopTransmitting()
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

    let rxAudio = RXAudioPlayer()
    private let makeController: (Connection, any RXAudioSink) -> any RadioControlling
    private let serialDevices: () -> [String]
    private let audioOutput: (any AudioOutput)?
    private let simulateSignal: (@Sendable (Bool) async -> Void)?
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
        simulateSignal: (@Sendable (Bool) async -> Void)? = nil
    ) {
        self.makeController = makeController
        self.serialDevices = serialDevices
        self.audioOutput = audioOutput
        self.simulateSignal = simulateSignal
        refreshConnections()
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
        await controller.connect()
    }

    public func disconnect() async {
        observer?.cancel()
        observer = nil
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
            frequencyText = Self.format(reported)
        }
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

    // MARK: Settings

    /// Tunes RX and TX to the entered frequency, normalised and clamped like the Android app.
    public func applyFrequency() async {
        guard isReady, let controller, let firmware = snapshot.firmware, let current = frequency else { return }
        guard let entered = Self.frequency(frequencyText, in: firmware.minRadioFreq...firmware.maxRadioFreq) else {
            message = "\"\(frequencyText)\" is not a frequency."
            frequencyText = Self.format(current)
            return
        }
        message = nil
        frequency = entered
        frequencyText = Self.format(entered)
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

    /// `RadioAudioService.makeSafeHamFreq`: `1467` → `146.7`, then clamped to the module range.
    static func frequency(_ text: String, in range: ClosedRange<Float>) -> Float? {
        guard var frequency = Float(text.trimmingCharacters(in: .whitespaces)), frequency.isFinite else { return nil }
        while frequency > 500 {
            frequency /= 10
        }
        return min(max(frequency, range.lowerBound), range.upperBound)
    }

    /// Four decimals, as in the Android app.
    static func format(_ frequency: Float) -> String {
        String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), Double(frequency))
    }

    private static func label(_ tone: UInt8) -> String {
        CTCSS.label(for: tone) ?? CTCSS.none
    }
}
