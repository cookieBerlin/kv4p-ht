import Testing

@testable import KV4PRadio

/// Stepping the frequency digit by digit, in the channel raster (ADR-0064).
@Suite("Frequency step")
struct FrequencyStepTests {
    static let vhf: ClosedRange<Float> = 134...174
    static let narrow = FrequencyStep.raster(isWide: false)
    static let wide = FrequencyStep.raster(isWide: true)

    static func step(
        _ frequency: Float,
        digit: Int,
        by count: Int = 1,
        raster: Int = narrow,
        exact: Bool = false
    ) -> Float {
        FrequencyStep.stepped(frequency, digit: digit, by: count, raster: raster, exact: exact, in: vhf)
    }

    @Test("the raster is 12.5 kHz narrow and 25 kHz wide")
    func raster() {
        #expect(Self.narrow == 12_500)
        #expect(Self.wide == 25_000)
        #expect(FrequencyStep.digits == [100_000_000, 10_000_000, 1_000_000, 100_000, 10_000, 1_000, 100])
    }

    @Test(
        "a digit at or above the raster steps by its value and snaps to the raster",
        arguments: [
            (Float(145.5), 1_000_000, 1, 146.5),
            (145.5, 100_000, 1, 145.6),
            (145.5, 100_000, -1, 145.4),
            (145.5, 10_000_000, -1, 135.5),
            (146.513, 100_000, 1, 146.6125),
            (146.519, 100_000, 1, 146.625),
            (146.52, 100_000, 1, 146.625),
        ] as [(Float, Int, Int, Float)]
    )
    func largeDigit(frequency: Float, digit: Int, count: Int, expected: Float) {
        #expect(Self.step(frequency, digit: digit, by: count) == expected)
    }

    @Test(
        "a digit below the raster steps by the raster",
        arguments: [
            (Float(145.5), 10_000, 1, FrequencyStep.raster(isWide: false), Float(145.5125)),
            (145.5, 1_000, -1, FrequencyStep.raster(isWide: false), 145.4875),
            (145.5, 100, 2, FrequencyStep.raster(isWide: false), 145.525),
            (145.5, 10_000, 1, FrequencyStep.raster(isWide: true), 145.525),
            (146.513, 100, 1, FrequencyStep.raster(isWide: false), 146.525),
        ] as [(Float, Int, Int, Int, Float)]
    )
    func smallDigit(frequency: Float, digit: Int, count: Int, raster: Int, expected: Float) {
        #expect(Self.step(frequency, digit: digit, by: count, raster: raster) == expected)
    }

    @Test("a tie snaps in the direction of the step")
    func tie() {
        // 146.50625 lies halfway between 146.5 and 146.5125.
        #expect(Self.step(146.40625, digit: 100_000, by: 1) == 146.5125)
        #expect(Self.step(146.60625, digit: 100_000, by: -1) == 146.5)
    }

    @Test("exactly: every digit steps by its value, off the raster")
    func exact() {
        #expect(Self.step(146.52, digit: 1_000, exact: true) == 146.521)
        #expect(Self.step(146.52, digit: 100, by: -1, exact: true) == 146.5199)
        #expect(Self.step(146.513, digit: 100_000, exact: true) == 146.613)
    }

    @Test("a step carries over")
    func carry() {
        #expect(Self.step(145.995, digit: 10_000, raster: Self.wide, exact: true) == 146.005)
        #expect(Self.step(146.0, digit: 100, by: -1, exact: true) == 145.9999)
    }

    @Test("a step stays within the radio's limits")
    func limits() {
        #expect(Self.step(173.5, digit: 1_000_000) == 174)
        #expect(Self.step(174, digit: 100_000) == 174)
        #expect(Self.step(134.05, digit: 100_000_000, by: -1) == 134)
    }

    @Test(
        "the digit under a character of the shown frequency",
        arguments: [
            ("146.5200", 0, 100_000_000),
            ("146.5200", 2, 1_000_000),
            ("146.5200", 3, nil),
            ("146,5200", 4, 100_000),
            ("146.5200", 7, 100),
            ("146.5200", 8, nil),
            ("146.5200", -1, nil),
            ("98.5000", 0, 10_000_000),
            ("1465200", 0, nil),
        ] as [(String, Int, Int?)]
    )
    func digitAtCharacter(text: String, index: Int, expected: Int?) {
        #expect(FrequencyStep.digit(atCharacter: index, in: text) == expected)
    }

    @Test(
        "the digit at the cursor: the one before it, or after it at a separator or the start",
        arguments: [
            ("146.5200", 3, 1_000_000),
            ("146.5200", 4, 100_000),
            ("146.5200", 5, 100_000),
            ("146.5200", 0, 100_000_000),
            ("146.5200", 8, 100),
            ("", 0, nil),
        ] as [(String, Int, Int?)]
    )
    func digitAtCursor(text: String, cursor: Int, expected: Int?) {
        #expect(FrequencyStep.digit(atCursor: cursor, in: text) == expected)
    }
}

@Suite("Number input")
struct NumberInputTests {
    @Test(
        "digits and at most one separator, a comma or a point",
        arguments: [
            ("146.52", "146.52"),
            ("146,52", "146,52"),
            ("146.5.2", "146.52"),
            ("146,5.2", "146,52"),
            ("1a4-6 .5", "146.5"),
            ("", ""),
        ]
    )
    func decimal(text: String, expected: String) {
        #expect(NumberInput.filtered(text, allowsSeparator: true) == expected)
    }

    @Test("whole numbers take no separator")
    func whole() {
        #expect(NumberInput.filtered("6.00,5", allowsSeparator: false) == "6005")
    }
}

@Suite("Scroll steps")
struct ScrollStepsTests {
    @Test("a scroll wheel steps once per notch")
    func wheel() {
        var steps = ScrollSteps()
        #expect(steps.steps(for: 1, isPrecise: false) == 1)
        #expect(steps.steps(for: -3, isPrecise: false) == -1)
        #expect(steps.steps(for: 0, isPrecise: false) == 0)
    }

    @Test("the many small steps of a trackpad are gathered")
    func trackpad() {
        var steps = ScrollSteps()
        let threshold = ScrollSteps.threshold
        #expect(steps.steps(for: threshold / 2, isPrecise: true) == 0)
        #expect(steps.steps(for: threshold / 2, isPrecise: true) == 1)
        #expect(steps.steps(for: threshold * 2.5, isPrecise: true) == 2)
        #expect(steps.steps(for: threshold / 2, isPrecise: true) == 1)
    }

    @Test("a change of direction starts again")
    func direction() {
        var steps = ScrollSteps()
        let threshold = ScrollSteps.threshold
        #expect(steps.steps(for: threshold * 0.9, isPrecise: true) == 0)
        #expect(steps.steps(for: -threshold * 0.5, isPrecise: true) == 0)
        #expect(steps.steps(for: -threshold * 0.5, isPrecise: true) == -1)
        steps.reset()
        #expect(steps.steps(for: -threshold * 0.5, isPrecise: true) == 0)
    }
}

@Suite("Frequency with the decimal separator of the language")
struct FrequencySeparatorTests {
    @Test("shown with the separator, read with a comma or a point")
    func separator() {
        #expect(HamFrequency.format(146.52, separator: ",") == "146,5200")
        #expect(HamFrequency.format(146.52, separator: ".") == "146.5200")
        #expect(HamFrequency.formatLimit(144.00625, separator: ",") == "144,00625")
        #expect(HamFrequency.parse("146,52") == 146.52)
        #expect(HamFrequency.parse(" 146.52 ") == 146.52)
        #expect(HamFrequency.parse("abc") == nil)
        #expect(HamFrequency.safe("146,52", in: FrequencyStepTests.vhf) == 146.52)
    }
}
