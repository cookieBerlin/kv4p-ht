import Foundation
import KV4PProtocol
import KV4PTestSupport
import KV4PTransport
import Testing

@testable import KV4PSimulator

/// The simulator as the user configures it in the app (ADR-0041).
@MainActor
@Suite("Simulator radio")
struct SimulatorRadioTests {
    @Test("by default it is a current VHF radio with everything working")
    func defaults() {
        let scenario = SimulatorSettings().scenario
        #expect(scenario.moduleType == .sa818VHF)
        #expect(scenario.firmwareVersion == Firmware.version)
        #expect(scenario.features.contains([.highLowPower, .freeDV2400B]))
        #expect(scenario.radioModuleStatus == .found)
        #expect(!scenario.faults.omitsHello)
        #expect(scenario.windowSize == Firmware.bleWindowSize)
        #expect(scenario.defaultFrequency == 145.5)
    }

    @Test("the settings change the radio")
    func changes() {
        var settings = SimulatorSettings()
        settings.band = .uhf
        settings.hasCurrentFirmware = false
        settings.hasFreeDVModem = false
        settings.hasPowerSwitch = false
        settings.hasRadioModule = false
        settings.answers = false
        let scenario = settings.scenario
        #expect(scenario.moduleType == .sa818UHF)
        #expect(scenario.defaultFrequency == 435)
        #expect(scenario.firmwareVersion == Firmware.version - 1)
        #expect(!scenario.features.contains(.freeDV2400B))
        #expect(!scenario.features.contains(.highLowPower))
        #expect(scenario.radioModuleStatus == .notFound)
        #expect(scenario.faults.omitsHello)
    }

    @Test("each strength shows as its value on the S-meter", arguments: SimulatedSignal.allCases)
    func strengths(signal: SimulatedSignal) {
        #expect(SMeter.value(rssi: signal.rssi) == signal.rawValue)
    }

    @Test("all values of the S-meter can be chosen, in order")
    func allStrengths() {
        #expect(SimulatedSignal.allCases.map(\.rawValue) == Array(0...SMeter.overload))
    }

    @Test("the bands are named")
    func bands() {
        #expect(SimulatedBand.allCases.map(\.label) == ["VHF", "UHF"])
    }

    @Test("the settings can be stored")
    func coding() throws {
        var settings = SimulatorSettings()
        settings.band = .uhf
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(SimulatorSettings.self, from: data) == settings)
    }

    @Test("a new transport uses the settings of that moment")
    func transportUsesSettings() async {
        let radio = SimulatorRadio(clock: ManualClock())
        radio.settings.band = .uhf
        let transport = radio.makeTransport()
        radio.settings.band = .vhf
        #expect(await transport.simulator.scenario.moduleType == .sa818UHF)
    }

    @Test("signal, packets and a lost connection reach the current transport")
    func actions() async throws {
        let radio = SimulatorRadio(clock: ManualClock())
        await radio.setSignal(.s9)
        await radio.loseConnection()
        await radio.hear([1])
        let transport = radio.makeTransport()
        var states = transport.states.makeAsyncIterator()
        var bytes = transport.incoming.makeAsyncIterator()
        try await transport.connect()
        _ = await bytes.next()
        await radio.setSignal(.s9)
        #expect(await transport.simulator.carrier?.rssi == SimulatedSignal.s9.rssi)
        #expect(await transport.simulator.carrier?.voiceFrames.isEmpty == false)
        await radio.setSignal(nil)
        #expect(await transport.simulator.carrier == nil)
        await radio.hear([0x82, 0xA0, 0x41])
        #expect(await bytes.next() != nil)
        await radio.loseConnection()
        var last: TransportState?
        while last != .failed(.connectionLost), let state = await states.next() {
            last = state
        }
        #expect(last == .failed(.connectionLost))
        await #expect(throws: TransportError.notConnected) { try await transport.send([1]) }
    }
}
