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
        #expect(settings.beaconAccuracy == .exact)
        #expect(settings.beaconFrequency == nil)
        #expect(!settings.isDigipeatingEnabled)
        #expect(!settings.isIGateEnabled)
        #expect(!settings.isInternetFeedEnabled)
        #expect(settings.aprsListFilter.isEmpty)
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
        settings.aprsListFilter = APRSListFilter(isForMe: true)
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

    @Test("the former switch for an approximate position becomes an accuracy of 1000 m")
    func formerApproximateSwitch() {
        #expect(AppSettings(data: Data(#"{"isBeaconApproximate": true}"#.utf8)).beaconAccuracy == .within1000m)
        #expect(AppSettings(data: Data(#"{"isBeaconApproximate": false}"#.utf8)).beaconAccuracy == .exact)
        let both = #"{"isBeaconApproximate": true, "beaconAccuracy": "within50m"}"#
        #expect(AppSettings(data: Data(both.utf8)).beaconAccuracy == .within50m)
    }

    @Test(
        "the accuracies round a position to steps of about their distance",
        arguments: [
            (BeaconAccuracy.exact, 49.0567, "Exact"),
            (.within50m, 49.0565, "50 m"),
            (.within100m, 49.057, "100 m"),
            (.within500m, 49.055, "500 m"),
            (.within1000m, 49.06, "1000 m"),
        ]
    )
    func accuracies(accuracy: BeaconAccuracy, rounded: Double, label: String) {
        #expect(abs(accuracy.rounded(49.0567) - rounded) < 0.000_01)
        #expect(accuracy.label == label)
    }

    @Test("the APRS beacon frequencies Android offers")
    func beaconFrequencies() {
        #expect(AppSettings.beaconFrequencyOptions == [144.39, 144.575, 144.64, 144.66, 144.8, 145.175, 145.825])
    }
}
