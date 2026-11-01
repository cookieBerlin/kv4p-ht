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
        TXBand(range: module == .sa818UHF ? 420...450 : 144...148)
    }

    /// The whole channel, `frequency` ± half the bandwidth (`0x01` = 25 kHz, else 12.5 kHz), lies within the band.
    public func allows(_ frequency: Float, bandwidth: UInt8) -> Bool {
        let halfBandwidth: Float = (bandwidth == 1 ? 0.025 : 0.0125) / 2
        return frequency >= range.lowerBound + halfBandwidth && frequency <= range.upperBound - halfBandwidth
    }
}
