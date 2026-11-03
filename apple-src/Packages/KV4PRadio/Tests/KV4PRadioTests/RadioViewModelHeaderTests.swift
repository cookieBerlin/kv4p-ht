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
