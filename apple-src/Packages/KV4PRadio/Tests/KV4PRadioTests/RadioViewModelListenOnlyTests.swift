import KV4PAPRS
import KV4PAudio
import KV4PTestSupport
import Testing

@testable import KV4PRadio

/// The callsign and listen-only: nothing goes out without one, or with the other (ADR-0047).
@MainActor
@Suite("Radio view model: callsign and listen-only")
struct RadioViewModelListenOnlyTests {
    static func plain(store: MemorySettingsStore = MemorySettingsStore()) -> RadioViewModel {
        RadioViewModel(
            makeController: { _, _ in RadioController(transport: ScriptedTransport()) },
            serialDevices: { [] },
            settings: store
        )
    }

    // MARK: Asking on start

    @Test("a start without a callsign asks; choosing one or listen-only ends this")
    func asks() {
        let model = Self.plain()
        #expect(model.isStationSetupPending)
        model.completeStationSetup(callsign: " n0call ")
        #expect(!model.isStationSetupPending)
        #expect(model.callsign == "N0CALL")

        let other = Self.plain()
        other.chooseListenOnly()
        #expect(!other.isStationSetupPending)
        #expect(other.isListenOnly)
    }

    @Test("what is entered counts; only an empty field keeps asking")
    func anythingEntered() {
        let model = Self.plain()
        model.completeStationSetup(callsign: "   ")
        #expect(model.isStationSetupPending)
        #expect(model.callsign.isEmpty)
        model.completeStationSetup(callsign: "ANYTHING")
        #expect(!model.isStationSetupPending)
    }

    @Test("a start with a callsign or listen-only stored does not ask; a callsign removed asks at the next start")
    func restored() {
        let store = MemorySettingsStore()
        let first = Self.plain(store: store)
        first.completeStationSetup(callsign: "N0CALL")
        #expect(!Self.plain(store: store).isStationSetupPending)

        first.callsign = ""
        #expect(!first.isStationSetupPending)  // not while typing in the settings
        #expect(Self.plain(store: store).isStationSetupPending)

        first.isListenOnly = true
        let listening = Self.plain(store: store)
        #expect(!listening.isStationSetupPending)
        #expect(listening.isListenOnly)
    }

    @Test("sending needs a callsign and no listen-only")
    func canSendOnAir() {
        let model = Self.plain()
        #expect(!model.canSendOnAir)
        model.callsign = "N0CALL"
        #expect(model.canSendOnAir)
        model.isListenOnly = true
        #expect(!model.canSendOnAir)
        model.callsign = ""
        #expect(!model.canSendOnAir)
    }

    @Test("the settings warn only about a missing callsign without listen-only")
    func stationWarning() {
        let model = Self.plain()
        #expect(model.stationWarning == "Without a callsign, nothing goes out. Enter one, or choose Listen only.")
        model.isListenOnly = true
        #expect(model.stationWarning == nil)
        model.isListenOnly = false
        model.callsign = "N0CALL"
        #expect(model.stationWarning == nil)
    }

    @Test("the text instead of PTT says why")
    func blockedText() {
        let model = Self.plain()
        #expect(model.transmitBlockedText == "Set your callsign to transmit.")
        model.isListenOnly = true
        #expect(model.transmitBlockedText == "Listen only: this app does not transmit.")
        model.callsign = "N0CALL"
        #expect(model.transmitBlockedText == "Listen only: this app does not transmit.")
        model.isListenOnly = false
        #expect(model.transmitBlockedText == nil)
    }

    // MARK: Voice

    @MainActor
    final class Voice {
        let setup = RadioViewModelTransmitTests.Setup()
        var model: RadioViewModel { setup.model }

        func tuned() async {
            model.callsign = "N0CALL"
            await setup.tuned()
        }

        func transmitting() async {
            await tuned()
            await model.pressPTT()
            #expect(model.isTransmitting)
        }
    }

    @Test("without a callsign or in listen-only, PTT does nothing")
    func pttBlocked() async {
        let voice = Voice()
        await voice.tuned()
        voice.model.callsign = ""
        await voice.model.pressPTT()
        #expect(!voice.model.isTransmitting)
        voice.model.callsign = "N0CALL"
        voice.model.isListenOnly = true
        await voice.model.pressPTT()
        #expect(!voice.model.isTransmitting)
    }

    @Test("removing the callsign ends a transmission at once")
    func callsignRemoved() async {
        let voice = Voice()
        await voice.transmitting()
        voice.model.callsign = ""
        #expect(await RadioViewModelTests.eventually(voice.model) { !$0.isTransmitting })
    }

    @Test("choosing listen-only ends a transmission at once")
    func listenOnlyChosen() async {
        let voice = Voice()
        await voice.transmitting()
        voice.model.isListenOnly = true
        #expect(await RadioViewModelTests.eventually(voice.model) { !$0.isTransmitting })
    }

    @Test("the access tone is not offered and does not go out")
    func toneBlocked() async {
        let voice = Voice()
        await voice.tuned()
        voice.model.accessToneHz = 1750
        #expect(voice.model.canSendAccessTone)
        voice.model.isListenOnly = true
        #expect(!voice.model.canSendAccessTone)
        await voice.model.pressAccessTone()
        #expect(!voice.model.isSendingAccessTone)
        #expect(!voice.model.isTransmitting)
    }

    // MARK: APRS

    @Test("a message does not go out, and says why")
    func messageBlocked() async {
        let aprs = RadioViewModelAPRSTests.Messaging()
        await aprs.connect()
        aprs.model.callsign = "N0CALL"
        aprs.model.isListenOnly = true
        aprs.model.sendAPRSMessage(to: "N1CALL", text: "Hello")
        #expect(aprs.model.message == "Listen only: this app does not transmit.")
        aprs.advance(by: 60_000)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await aprs.sent.isEmpty)
    }

    @Test("a message to us gets no acknowledgement")
    func noAcknowledgement() async throws {
        let aprs = RadioViewModelAPRSTests.Messaging()
        await aprs.connect()
        aprs.model.callsign = "N0CALL"
        aprs.model.isListenOnly = true
        try await aprs.hear("N1CALL>APRS::N0CALL   :Hello{001")
        #expect(await RadioViewModelTests.eventually(aprs.model) { !$0.aprsEvents.isEmpty })
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await aprs.sent.isEmpty)
    }

    @Test("nothing is digipeated, and the setting stays for later")
    func noDigipeat() async throws {
        let aprs = RadioViewModelAPRSTests.Messaging()
        await aprs.connect()
        aprs.model.callsign = "N0CALL"
        aprs.model.isDigipeatingEnabled = true
        aprs.model.isListenOnly = true
        try await aprs.hear("N1CALL>APRS,WIDE1-1:>on air")
        #expect(await RadioViewModelTests.eventually(aprs.model) { !$0.aprsEvents.isEmpty })
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await aprs.sent.isEmpty)
        #expect(aprs.model.isDigipeatingEnabled)
    }

    @Test("no beacon goes out, and the setting stays for later")
    func noBeacon() async {
        let setup = RadioViewModelBeaconTests.Setup()
        await setup.connect()
        setup.model.callsign = "N0CALL"
        setup.model.isListenOnly = true
        setup.model.isBeaconEnabled = true
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await setup.sent.isEmpty)
        #expect(setup.model.isBeaconEnabled)
    }

    // MARK: APRS-IS

    @Test("without a callsign nothing is connected or sent, also with the iGate on")
    func internetNeedsCallsign() {
        let setup = RadioViewModelInternetTests.Setup()
        setup.model.isIGateEnabled = true
        setup.model.isInternetFeedEnabled = true
        #expect(setup.link.settings.last?.isEnabled == false)
        setup.model.callsign = "N0CALL"
        #expect(setup.link.settings.last?.isEnabled == true)
        setup.model.callsign = ""
        #expect(setup.link.settings.last?.isEnabled == false)
    }

    @Test("in listen-only with a callsign, the iGate and the feed stay available")
    func internetInListenOnly() {
        let setup = RadioViewModelInternetTests.Setup()
        setup.model.callsign = "N0CALL"
        setup.model.isListenOnly = true
        setup.model.isIGateEnabled = true
        #expect(setup.link.settings.last?.isEnabled == true)
        #expect(setup.model.canUseInternetWithCallsign)
        setup.model.callsign = ""
        #expect(!setup.model.canUseInternetWithCallsign)
    }

    @Test("the choice is stored in the settings")
    func stored() {
        let store = MemorySettingsStore()
        let model = Self.plain(store: store)
        model.isListenOnly = true
        #expect(store.settings.isListenOnly)
    }
}
