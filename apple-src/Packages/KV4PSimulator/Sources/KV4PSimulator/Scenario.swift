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
    /// The current firmware source, which has the FreeDV 2400B modem (`getFirmwareFeatures`), over BLE.
    public static let freeDV = ble.with { $0.features.insert(.freeDV2400B) }

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

/// A received signal: it opens the squelch and plays a tone (the squelch level is not simulated). A FreeDV 2400B
/// signal carries `voiceFrames`, which the modem decodes in FreeDV mode; analog, it still sounds like the tone.
public struct Carrier: Equatable, Sendable {
    public var toneHz: Int
    public var amplitude: Int16
    /// Raw SA818 RSSI, reported with `RSSI_ENABLED`.
    public var rssi: UInt8
    /// Codec2 1300 frames, repeated; empty for an analog signal.
    public var voiceFrames: [[UInt8]]

    public init(toneHz: Int = 1000, amplitude: Int16 = 8000, rssi: UInt8 = 100, voiceFrames: [[UInt8]] = []) {
        self.toneHz = toneHz
        self.amplitude = amplitude
        self.rssi = rssi
        self.voiceFrames = voiceFrames
    }

    /// A FreeDV 2400B signal: in FreeDV mode a voiced sound with rising pitch, analog the tone. The frames are the
    /// "voiced" vector of `tools/codec2-vectors`, which pins them.
    public static let freeDVVoice = Carrier(
        voiceFrames: [
            [0xF3, 0x9B, 0x06, 0x57, 0x5C, 0xDD, 0x20], [0xF2, 0xF4, 0x06, 0x57, 0x5C, 0xDD, 0x20],
            [0xF2, 0x56, 0x06, 0x57, 0x5C, 0xDD, 0x20], [0xF2, 0x13, 0x06, 0x47, 0x5D, 0xDD, 0x20],
            [0xF6, 0x31, 0x06, 0x47, 0x5C, 0xDD, 0x20], [0xF6, 0xD0, 0x06, 0x47, 0x5C, 0xDD, 0x20],
            [0xF6, 0xB0, 0x06, 0x47, 0x5C, 0xDD, 0x20], [0xF7, 0xB0, 0x06, 0x47, 0x5C, 0xDD, 0x20],
            [0xF7, 0xD0, 0x06, 0x47, 0x5C, 0xDD, 0x20], [0xF7, 0x30, 0x06, 0x47, 0x5C, 0xDD, 0x20],
            [0xF5, 0x10, 0x06, 0x47, 0x5C, 0xDD, 0x20], [0xF5, 0x50, 0x17, 0x47, 0x5D, 0xDD, 0x20],
            [0xF5, 0xF1, 0x17, 0x47, 0x5D, 0xDD, 0x20], [0xF4, 0x92, 0x17, 0x47, 0x5C, 0xDD, 0x20],
            [0xF4, 0xF5, 0x17, 0x47, 0x4D, 0xDD, 0x20], [0xF4, 0x7E, 0x17, 0x47, 0x4D, 0xDD, 0x20],
        ]
    )

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
