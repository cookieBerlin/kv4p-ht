import Testing

@testable import KV4PProtocol
@testable import KV4PRadio

/// `RadioAudioService.canTransmitOnFrequency` with the default band limits of the Android app.
@Suite("TX band")
struct TXBandTests {
    @Test("defaults: 2 m for VHF, 70 cm for UHF modules")
    func defaults() {
        #expect(TXBand.default(for: .sa818VHF).range == 144...148)
        #expect(TXBand.default(for: .sa818UHF).range == 420...450)
    }

    @Test(
        "the whole channel must lie within the band",
        arguments: [
            (Float(144.0), UInt8(1), false),
            (144.02, 1, true),
            (146.52, 1, true),
            (147.98, 1, true),
            (147.99, 1, false),
            (147.99, 0, true),
            (148.0, 0, false),
            (143.5, 0, false),
        ] as [(Float, UInt8, Bool)]
    )
    func allows(frequency: Float, bandwidth: UInt8, allowed: Bool) {
        #expect(TXBand.default(for: .sa818VHF).allows(frequency, bandwidth: bandwidth) == allowed)
    }

    @Test("UHF")
    func uhf() {
        let band = TXBand.default(for: .sa818UHF)
        #expect(band.allows(446, bandwidth: 0))
        #expect(!band.allows(420, bandwidth: 0))
        #expect(!band.allows(146.52, bandwidth: 0))
    }
}
