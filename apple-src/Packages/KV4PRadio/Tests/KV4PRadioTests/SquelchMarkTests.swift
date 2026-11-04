import Testing

@testable import KV4PRadio

/// The squelch mark on the S-meter (ADR-0050).
@MainActor
@Suite("Squelch mark")
struct SquelchMarkTests {
    private static let width = 258.0
    private static let spacing = 2.0

    private static func level(at position: Double) -> Int {
        SquelchMark.level(at: position, width: width, spacing: spacing)
    }

    @Test("level n stands in the gap after bar n")
    func position() {
        // Each of the 13 bars takes 20 points with its gap of 2, so a gap's middle is at 19, 39, …
        #expect(SquelchMark.position(of: 0, width: Self.width, spacing: Self.spacing) == -1)
        #expect(SquelchMark.position(of: 1, width: Self.width, spacing: Self.spacing) == 19)
        #expect(SquelchMark.position(of: 8, width: Self.width, spacing: Self.spacing) == 159)
    }

    @Test("every level is found again at its own position", arguments: SquelchMark.levels)
    func roundTrip(level: Int) {
        #expect(Self.level(at: SquelchMark.position(of: level, width: Self.width, spacing: Self.spacing)) == level)
    }

    @Test("a position counts for the nearest level")
    func nearest() {
        #expect(Self.level(at: 28) == 1)
        #expect(Self.level(at: 30) == 2)
    }

    @Test("beyond the levels, the mark stays at the last one")
    func clamped() {
        #expect(Self.level(at: -40) == 0)
        #expect(Self.level(at: Self.width) == 8)
        #expect(Self.level(at: Self.width + 100) == 8)
    }

    @Test("the mark changes the squelch of a connected radio, within its levels")
    func change() async {
        let model = RadioViewModelTests.model(.ble)
        model.changeSquelch(to: 5)
        #expect(model.squelch != 5)
        #expect(!model.canChangeSquelch)
        await model.connect()
        #expect(await RadioViewModelTests.eventually(model) { $0.isReady })
        #expect(model.canChangeSquelch)
        model.changeSquelch(to: 5)
        #expect(await RadioViewModelTests.eventually(model) { $0.squelch == 5 })
        model.changeSquelch(to: 9)
        #expect(await RadioViewModelTests.eventually(model) { $0.squelch == 8 })
        model.changeSquelch(to: -1)
        #expect(await RadioViewModelTests.eventually(model) { $0.squelch == 0 })
    }
}
