import KV4PProtocol

/// The band of the simulated radio module.
public enum SimulatedBand: String, Codable, CaseIterable, Sendable {
    case vhf, uhf

    public var label: String {
        switch self {
        case .vhf: "VHF"
        case .uhf: "UHF"
        }
    }
}

/// A received signal of a given strength.
public enum SimulatedSignal: String, CaseIterable, Sendable {
    case s3, s9, s9Plus40, overload

    public var label: String {
        switch self {
        case .s3: "S3"
        case .s9: "S9"
        case .s9Plus40: "S9+40"
        case .overload: "Overload"
        }
    }

    /// The raw SA818 RSSI that `SMeter` shows as `label`.
    var rssi: UInt8 {
        switch self {
        case .s3: 27
        case .s9: 57
        case .s9Plus40: 90
        case .overload: 110
        }
    }
}

/// What the user can choose about the simulated radio; takes effect at the next connection.
public struct SimulatorSettings: Codable, Equatable, Sendable {
    public var band = SimulatedBand.vhf
    /// Otherwise a version older than the app requires.
    public var hasCurrentFirmware = true
    public var hasFreeDVModem = true
    public var hasPowerSwitch = true
    public var hasRadioModule = true
    /// Otherwise the radio never sends `HELLO`.
    public var answers = true

    public init() {}

    public var scenario: Scenario {
        var scenario = Scenario.ble
        scenario.moduleType = band == .uhf ? .sa818UHF : .sa818VHF
        scenario.firmwareVersion = hasCurrentFirmware ? Firmware.version : Firmware.version - 1
        if hasFreeDVModem { scenario.features.insert(.freeDV2400B) }
        if !hasPowerSwitch { scenario.features.remove(.highLowPower) }
        scenario.radioModuleStatus = hasRadioModule ? .found : .notFound
        scenario.faults.omitsHello = !answers
        return scenario
    }
}

/// What the app can do with the simulator while it is connected.
@MainActor
public protocol SimulatorControlling: AnyObject {
    var settings: SimulatorSettings { get set }
    /// A signal starts or, with `nil`, ends on the receive frequency.
    func setSignal(_ signal: SimulatedSignal?) async
    /// The link fails, as when a radio goes out of range.
    func loseConnection() async
    /// An AX.25 packet (without FCS) received on air.
    func hear(_ frame: [UInt8]) async
}

/// The simulator of the current connection.
@MainActor
public final class SimulatorRadio<C: Clock>: SimulatorControlling where C.Duration == Duration {
    public var settings = SimulatorSettings()
    private let clock: C
    private var transport: SimulatorTransport<C>?

    public init(clock: C) {
        self.clock = clock
    }

    public func makeTransport() -> SimulatorTransport<C> {
        let transport = SimulatorTransport(simulator: RadioSimulator(scenario: settings.scenario), clock: clock)
        self.transport = transport
        return transport
    }

    public func setSignal(_ signal: SimulatedSignal?) async {
        var carrier = signal.map { _ in Carrier.freeDVVoice }
        carrier?.rssi = signal?.rssi ?? 0
        await transport?.setCarrier(carrier)
    }

    public func loseConnection() async {
        await transport?.loseConnection()
    }

    public func hear(_ frame: [UInt8]) async {
        await transport?.hear(frame)
    }
}
