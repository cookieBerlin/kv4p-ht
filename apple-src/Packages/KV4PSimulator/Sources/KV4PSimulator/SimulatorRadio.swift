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

/// A received signal, with a strength for each value of `SMeter`, which is its raw value.
public enum SimulatedSignal: Int, CaseIterable, Sendable {
    case s0, s1, s2, s3, s4, s5, s6, s7, s8, s9, s9Plus20, s9Plus40, s9Plus60, overload

    public var label: String {
        switch self {
        case .s9Plus20: "S9+20"
        case .s9Plus40: "S9+40"
        case .s9Plus60: "S9+60"
        case .overload: "Overload"
        default: "S\(rawValue)"
        }
    }

    /// The raw SA818 RSSI that `SMeter` shows as this value.
    var rssi: UInt8 {
        [0, 17, 22, 27, 32, 37, 42, 47, 52, 57, 74, 90, 107, 110][rawValue]
    }

    /// Every strength up to overload and back, one after the other.
    public static let ramp = allCases + allCases.dropLast().reversed()

    private static let fullLevel = 8000

    /// The signal as it sounds. FM stays equally loud in reality; here the tone grows out of the noise on purpose, so
    /// that the strengths can be told apart by ear.
    var carrier: Carrier {
        let levels = [0, 5, 10, 20, 30, 45, 60, 75, 90, 100, 100, 100, 100, 100]
        let noises = [25, 25, 25, 25, 20, 15, 10, 6, 3, 0, 0, 0, 0, 0]
        var carrier = Carrier.freeDVVoice
        carrier.rssi = rssi
        carrier.amplitude = Int16(Self.fullLevel * levels[rawValue] / 100)
        carrier.noiseAmplitude = Int16(Self.fullLevel * noises[rawValue] / 100)
        carrier.isDistorted = self == .overload
        return carrier
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
        scenario.startFrequency = band == .uhf ? 435 : 145.5  // the firmware's 144 MHz is at the band edge
        scenario.firmwareVersion = hasCurrentFirmware ? Firmware.version : Firmware.version - 1
        if hasFreeDVModem { scenario.features.insert(.freeDV2400B) }
        if !hasPowerSwitch { scenario.features.remove(.highLowPower) }
        scenario.radioModuleStatus = hasRadioModule ? .found : .notFound
        scenario.faults.omitsHello = !answers
        scenario.startSquelch = 3  // shows the squelch at work; 0 would keep the speaker on
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
        await transport?.setCarrier(signal?.carrier)
    }

    public func loseConnection() async {
        await transport?.loseConnection()
    }

    public func hear(_ frame: [UInt8]) async {
        await transport?.hear(frame)
    }
}
