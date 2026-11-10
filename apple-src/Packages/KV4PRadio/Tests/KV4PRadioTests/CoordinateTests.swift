import Testing

@testable import KV4PRadio

/// Latitude and longitude as the memory form shows and reads them (ADR-0065).
@Suite("Coordinate")
struct CoordinateTests {
    @Test(
        "decimal degrees, to five decimals, with the separator of the user's language",
        arguments: [
            (52 + 31 / 60.0, ",", "52,51667"), (-45.25, ",", "-45,25"), (12, ".", "12"), (-0.000_001, ".", "0"),
            (nil, ",", ""),
        ] as [(Double?, String, String)]
    )
    func format(value: Double?, separator: String, expected: String) {
        #expect(Coordinate.format(value, separator: separator) == expected)
    }

    @Test("a field is read with a comma or a point; empty is none, anything else not a number")
    func parse() throws {
        #expect(Coordinate.parse("-12,5") == -12.5)
        #expect(Coordinate.parse(" 52.5 ") == 52.5)
        #expect(Coordinate.parse("") == nil)
        #expect(Coordinate.parse("  ") == nil)
        #expect(try #require(Coordinate.parse("-")).isNaN)
    }
}
