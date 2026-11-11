import Foundation
import KV4PAPRS
import KV4PTestSupport
import Testing

@testable import KV4PRadio

/// APRS can be switched off as a whole, and then hides and does nothing (ADR-0066).
@MainActor
@Suite("APRS off")
struct APRSOffTests {
    @Test("APRS is on by default and stays on this device")
    func setting() throws {
        #expect(AppSettings().isAPRSEnabled)
        var settings = AppSettings()
        settings.isAPRSEnabled = false
        #expect(!AppSettings(data: try settings.encoded()).isAPRSEnabled)
        #expect(SettingsSync.values(of: settings) == SettingsSync.values(of: AppSettings()))
        let store = MemorySettingsStore(settings)
        let model = RadioViewModelSettingsTests.model(store)
        #expect(!model.isAPRSEnabled)
        model.isAPRSEnabled = true
        #expect(store.settings.isAPRSEnabled)
    }

    @Test("off, packets heard are ignored and messages to us are not acknowledged")
    func receivesNothing() async throws {
        let setup = RadioViewModelAPRSTests.Messaging()
        await setup.connect()
        setup.model.callsign = "N0CALL"
        setup.model.isAPRSEnabled = false
        try await setup.hear("N1CALL>APRS::N0CALL   :hello{7")
        setup.advance(by: 1_000)
        try await Task.sleep(for: .milliseconds(50))
        #expect(setup.model.aprsEvents.isEmpty)
        #expect(await setup.sent.isEmpty)
        setup.model.isAPRSEnabled = true
        try await setup.hear("N1CALL>APRS::N0CALL   :again{8")
        #expect(await RadioViewModelTests.eventually(setup.model) { $0.aprsEvents.count == 1 })
    }

    @Test("off, no message goes out and pending ones are not retried")
    func sendsNothing() async throws {
        let setup = RadioViewModelAPRSTests.Messaging()
        await setup.connect()
        setup.model.callsign = "N0CALL"
        setup.model.sendAPRSMessage(to: "N1CALL", text: "hi")
        #expect(await eventually { await setup.sent.count == 1 })
        setup.model.isAPRSEnabled = false
        setup.advance(by: 15_000)
        setup.model.sendAPRSMessage(to: "N1CALL", text: "not sent")
        try await Task.sleep(for: .milliseconds(50))
        #expect(await setup.sent.count == 1)
        #expect(setup.model.aprsEvents.count == 1)
    }

    @Test("off, no beacon goes out and the session for the background ends")
    func beaconsNothing() async throws {
        let setup = BackgroundBeaconTests.Setup()
        await setup.connect()
        setup.model.isBeaconEnabled = true
        #expect(await setup.waitForBeacons(1))
        #expect(setup.session.isRunning)
        setup.model.isAPRSEnabled = false
        #expect(!setup.session.isRunning)
        setup.time.advance(by: 300_000)
        try await Task.sleep(for: .milliseconds(50))
        #expect(await setup.sentCount == 1)
        #expect(setup.model.isBeaconEnabled, "The setting stays for when APRS is on again")
        setup.model.isAPRSEnabled = true
        #expect(setup.session.isRunning)
    }

    @Test("off, APRS-IS is not connected, though iGate and the feed stay on")
    func noInternet() async throws {
        let setup = RadioViewModelInternetTests.Setup()
        setup.model.callsign = "N0CALL"
        setup.model.isIGateEnabled = true
        #expect(setup.link.settings.last?.isEnabled == true)
        setup.model.isAPRSEnabled = false
        #expect(setup.link.settings.last?.isEnabled == false)
        #expect(setup.model.isIGateEnabled)
        setup.link.receive.yield("N1CALL>APRS,TCPIP*:>still on the way")
        try await Task.sleep(for: .milliseconds(50))
        #expect(setup.model.aprsEvents.isEmpty)
        setup.model.isAPRSEnabled = true
        #expect(setup.link.settings.last?.isEnabled == true)
    }
}
