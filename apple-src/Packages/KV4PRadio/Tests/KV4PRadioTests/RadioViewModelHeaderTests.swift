import KV4PPersistence
import KV4PProtocol
import KV4PSimulator
import Testing

@testable import KV4PRadio

/// What the header above the memories and APRS shows (ADR-0040).
@MainActor
@Suite("Radio view model: header")
struct RadioViewModelHeaderTests {
    @Test("the band follows the radio module", arguments: [(Scenario.ble, "VHF"), (Scenario.uhf, "UHF")])
    func band(scenario: Scenario, band: String) async {
        let model = RadioViewModelTests.model(scenario)
        #expect(model.bandText == nil)
        await model.connect()
        #expect(await RadioViewModelTests.eventually(model) { $0.isReady })
        #expect(model.bandText == band)
    }

    @Test("the name of the active memory is shown while tuned to it")
    func memoryName() async throws {
        let repository = try SwiftDataMemoryRepository.inMemory()
        let model = RadioViewModelMemoryTests.model(repository)
        await model.connect()
        #expect(await RadioViewModelTests.eventually(model) { $0.isReady && $0.snapshot.isInSync })
        await model.save(RadioViewModelMemoryTests.simplex)
        #expect(model.activeMemoryName == nil)
        await model.tune(to: try #require(model.memories.first))
        #expect(await RadioViewModelTests.eventually(model) { $0.activeMemoryId != nil })
        #expect(model.activeMemoryName == "Simplex")
    }

    @Test("the S-meter has a bar for each value up to overload")
    func bars() {
        #expect(RadioViewModel.sMeterBarCount == SMeter.overload)
    }
}

/// Problems that are not a failed connection, which the app shows until the user dismisses them.
@MainActor
@Suite("Radio view model: notices")
struct RadioViewModelNoticeTests {
    @Test("a problem is a notice until the user dismisses it")
    func notice() async {
        let model = RadioViewModelTests.model()
        #expect(model.notice == nil)
        await model.importRepeaterBook("not a csv", group: "Group")
        let notice = model.notice
        #expect(notice != nil)
        #expect(notice == model.message)
        model.dismissNotice()
        #expect(model.notice == nil)
        #expect(model.message == nil)
    }

    @Test("a failed connection shows as the status, not as a notice")
    func failure() async {
        let model = RadioViewModelTests.model(.noRadioModule)
        #expect(!model.hasFailed)
        await model.connect()
        #expect(await RadioViewModelTests.eventually(model) { $0.hasFailed })
        #expect(model.message != nil)
        #expect(model.notice == nil)
    }
}
