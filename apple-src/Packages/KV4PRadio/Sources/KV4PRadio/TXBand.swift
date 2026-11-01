import KV4PProtocol

/// The frequencies the app may transmit on (Android `RadioAudioService.canTransmitOnFrequency`).
public struct TXBand: Equatable, Sendable {
    /// MHz.
    public var range: ClosedRange<Float>

    public init(range: ClosedRange<Float>) {
        self.range = range
    }

    /// The default limits of the Android app: 2 m for VHF modules, 70 cm for UHF modules.
    public static func `default`(for module: RFModuleType) -> TXBand {
        TXLimits().band(for: module)
    }

    /// The whole channel, `frequency` ± half the bandwidth (`0x01` = 25 kHz, else 12.5 kHz), lies within the band.
    public func allows(_ frequency: Float, bandwidth: UInt8) -> Bool {
        let halfBandwidth: Float = (bandwidth == 1 ? 0.025 : 0.0125) / 2
        return frequency >= range.lowerBound + halfBandwidth && frequency <= range.upperBound - halfBandwidth
    }
}

/// The TX limits of the settings (Android `min2mTxFreq` … `max70cmTxFreq`), MHz; `updateTxLimitsForBand` picks the
/// band of the radio module.
public struct TXLimits: Codable, Equatable, Sendable {
    public var min2m: Float = 144
    public var max2m: Float = 148
    public var min70cm: Float = 420
    public var max70cm: Float = 450

    /// The choices of `SettingsActivity.populateMinFrequencies` and `populateMaxFrequencies`.
    public static let min2mOptions: [Float] = [144]
    public static let max2mOptions: [Float] = [148, 146]
    public static let min70cmOptions: [Float] = [420, 430]
    public static let max70cmOptions: [Float] = [450, 440]

    public init() {}

    public func band(for module: RFModuleType) -> TXBand {
        TXBand(range: module == .sa818UHF ? min70cm...max70cm : min2m...max2m)
    }
}
