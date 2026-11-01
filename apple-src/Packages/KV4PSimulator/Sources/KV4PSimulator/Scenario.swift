import Foundation
import KV4PProtocol

/// Describes the simulated device and the faults it injects (ADR-0014 C).
public struct Scenario: Equatable, Sendable {
    public var firmwareVersion = Firmware.version
    public var radioModuleStatus = RadioModuleStatus.found
    public var moduleType = RFModuleType.sa818VHF
    public var features: FirmwareFeatures = [.highLowPower, .esp32AFSK]
    public var windowSize = Firmware.usbWindowSize
    /// Desired state stored in flash; `nil` for a new device.
    public var storedState: RadioState?
    /// A signal on the receive frequency from power-on; `nil` for an idle channel.
    public var carrier: Carrier?
    public var faults = Faults()

    public init() {}

    public static let uhf = Scenario().with { $0.moduleType = .sa818UHF }
    public static let ble = Scenario().with { $0.windowSize = Firmware.bleWindowSize }
    public static let noRadioModule = Scenario().with { $0.radioModuleStatus = .notFound }

    /// `moduleMinRadioFreq()` … `moduleMaxRadioFreq()`, MHz.
    var frequencyRange: ClosedRange<Float> { moduleType == .sa818UHF ? 400...480 : 134...174 }

    /// `moduleDefaultRadioFreq()`, MHz.
    var defaultFrequency: Float { moduleType == .sa818UHF ? 435 : 144 }

    private func with(_ change: (inout Scenario) -> Void) -> Scenario {
        var scenario = self
        change(&scenario)
        return scenario
    }
}

/// A received signal: it opens the squelch and plays a tone (the squelch level is not simulated).
public struct Carrier: Equatable, Sendable {
    public var toneHz: Int
    public var amplitude: Int16
    /// Raw SA818 RSSI, reported with `RSSI_ENABLED`.
    public var rssi: UInt8

    public init(toneHz: Int = 1000, amplitude: Int16 = 8000, rssi: UInt8 = 100) {
        self.toneHz = toneHz
        self.amplitude = amplitude
        self.rssi = rssi
    }

    /// Sample `index` of the tone; `index` counts from 0 to `KV4P.audioSampleRate`, so the phase never drifts.
    func sample(_ index: Int) -> Int16 {
        let phase = 2 * Double.pi * Double(toneHz) * Double(index) / Double(KV4P.audioSampleRate)
        return Int16((Double(amplitude) * sin(phase)).rounded())
    }
}

/// Faults injected by a scenario.
public struct Faults: Equatable, Sendable {
    /// The device never sends `HELLO`, like firmware without the KV4P protocol.
    public var omitsHello = false
    /// Bytes sent before `HELLO`, e.g. boot log output on USB.
    public var garbageBeforeHello: [UInt8] = []
    /// The device never sends `WINDOW_UPDATE`.
    public var dropsWindowUpdates = false
    /// The SA818 answers at boot but not afterwards, so the next radio command stalls the firmware.
    public var radioModuleStopsResponding = false

    public init() {}
}
