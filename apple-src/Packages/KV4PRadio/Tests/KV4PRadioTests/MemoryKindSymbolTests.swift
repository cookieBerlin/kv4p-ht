import KV4PPersistence
import Testing

@testable import KV4PRadio

/// Each kind of memory has a name and a symbol of its own, and a row says its kind to VoiceOver (ADR-0065).
@MainActor
@Suite("Memory kind symbols")
struct MemoryKindSymbolTests {
    nonisolated private static let cases: [(MemoryKind, String, String)] = [
        (.frequency, "Frequency", "dial.medium"),
        (.repeater, "Repeater", "antenna.radiowaves.left.and.right"),
        (.beacon, "Beacon", "light.beacon.max"),
    ]

    @Test("each kind has its name and symbol", arguments: cases)
    func symbols(kind: MemoryKind, title: String, symbol: String) {
        #expect(kind.title == title)
        #expect(kind.symbol == symbol)
    }

    @Test("no two kinds share a symbol")
    func distinct() {
        #expect(Set(MemoryKind.allCases.map(\.symbol)).count == MemoryKind.allCases.count)
    }

    @Test("a row says the kind of every memory, the name, the frequency and the comment where it shows")
    func spoken() {
        let model = RadioViewModelTests.model()
        let frequency = ChannelMemory(name: "Calling channel", frequency: 145.5, comment: "Simplex")
        let beacon = ChannelMemory(name: "Local beacon", frequency: 144.49, kind: .beacon)
        #expect(
            model.spokenRow(frequency, withComment: true)
                == "Frequency, Calling channel, \(model.shown(145.5)) MHz, Simplex"
        )
        #expect(
            model.spokenRow(frequency, withComment: false) == "Frequency, Calling channel, \(model.shown(145.5)) MHz"
        )
        #expect(model.spokenRow(beacon, withComment: true) == "Beacon, Local beacon, \(model.shown(144.49)) MHz")
    }
}
