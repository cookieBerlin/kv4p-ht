import KV4PFlasher
import Testing

@testable import KV4PRadio

/// What the user reads before choosing a firmware (ADR-0049).
@MainActor
@Suite("Firmware choice text")
struct FirmwareChoiceTextTests {
    @Test("the nightly build is for this app, with its build time, commit and checksum")
    func forThisApp() {
        let choice = RadioViewModelFirmwareTests.forThisApp
        #expect(choice.title == "Nightly build, for this app")
        #expect(choice.isForThisApp)
        #expect(choice.suitability.contains("Sound, USB and Bluetooth LE work with this app."))
        #expect(choice.suitability.contains("development build"))
        #expect(choice.details == ["Built 2026-10-17 07:52 UTC, commit a7c6b4d", "SHA-256 aa11"])
    }

    @Test("firmware 17 says clearly that it is only for Android")
    func forAndroid() {
        let choice = RadioViewModelFirmwareTests.forAndroid
        #expect(choice.title == "Firmware 17, only for the Android app")
        #expect(!choice.isForThisApp)
        #expect(choice.suitability.contains("This app does not connect to it"))
        #expect(choice.suitability.contains("no Bluetooth LE"))
        #expect(choice.details == ["SHA-256 bb22"])
    }
}
