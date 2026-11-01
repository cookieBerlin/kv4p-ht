import Foundation
import KV4PAPRS
import KV4PAudio
import Testing

@testable import KV4PRadio

/// The app settings Android keeps in `AppSetting` rows.
@Suite("App settings")
struct AppSettingsTests {
    @Test("defaults are Android's")
    func defaults() {
        let settings = AppSettings()
        #expect(settings.callsign == "")
        #expect(settings.micGain == .none)
        #expect(!settings.isStickyPTT)
        #expect(!settings.isBeaconEnabled)
        #expect(settings.beaconSymbol == .phone)
        #expect(!settings.isBeaconApproximate)
        #expect(settings.beaconFrequency == nil)
        #expect(!settings.isDigipeatingEnabled)
        #expect(!settings.isIGateEnabled)
        #expect(!settings.isInternetFeedEnabled)
        #expect(settings.aprsDestinationFilter == .all)
        #expect(settings.txLimits == TXLimits())
        #expect(settings.selectedGroup == nil)
    }

    @Test("settings survive encoding; missing or unreadable values fall back to the defaults")
    func coding() throws {
        var settings = AppSettings()
        settings.callsign = "N0CALL"
        settings.micGain = .high
        settings.beaconSymbol = .car
        settings.beaconFrequency = 144.39
        settings.aprsDestinationFilter = .mine
        settings.txLimits.max2m = 146
        settings.selectedGroup = "Repeaters"
        #expect(AppSettings(data: try settings.encoded()) == settings)
        let partial = Data(#"{"callsign": "N1CALL", "micGain": "loud"}"#.utf8)
        var expected = AppSettings()
        expected.callsign = "N1CALL"
        #expect(AppSettings(data: partial) == expected)
        #expect(AppSettings(data: Data("x".utf8)) == AppSettings())
        #expect(AppSettings(data: nil) == AppSettings())
    }

    @Test("the APRS beacon frequencies Android offers")
    func beaconFrequencies() {
        #expect(AppSettings.beaconFrequencyOptions == [144.39, 144.575, 144.64, 144.66, 144.8, 145.175, 145.825])
    }
}
