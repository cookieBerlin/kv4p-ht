import Testing

@testable import KV4PProtocol

/// What each module receives, as the firmware gives it (`moduleMinRadioFreq`, `moduleMaxRadioFreq`).
@Suite("RF module type")
struct RFModuleTypeTests {
    @Test("VHF receives 134 to 174 MHz, UHF 400 to 480 MHz")
    func ranges() {
        #expect(RFModuleType.allCases == [.sa818VHF, .sa818UHF])
        #expect(RFModuleType.sa818VHF.frequencyRange == 134...174)
        #expect(RFModuleType.sa818UHF.frequencyRange == 400...480)
        #expect(RFModuleType.sa818VHF.band == "2 m")
        #expect(RFModuleType.sa818UHF.band == "70 cm")
        #expect(RFModuleType.receiving(439.1625) == .sa818UHF)
        #expect(RFModuleType.receiving(145.6) == .sa818VHF)
        #expect(RFModuleType.receiving(1296.9) == nil)
    }
}
