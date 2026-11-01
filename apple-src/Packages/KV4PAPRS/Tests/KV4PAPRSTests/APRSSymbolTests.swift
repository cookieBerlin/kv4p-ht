import Testing

@testable import KV4PAPRS

/// The beacon symbols of the Android app (`APRSIconType`).
@Suite("APRS symbols")
struct APRSSymbolTests {
    @Test("codes and names as in the Android app")
    func symbols() {
        #expect(String(APRSSymbol.allCases.map(\.code)) == "$[-b>jk<vRug'XYs")
        #expect(APRSSymbol.allCases.map(\.name) == [
            "Phone", "Person", "House", "Bicycle", "Car", "Jeep", "Truck", "Motorcycle", "Van", "RV", "18-wheeler",
            "Glider", "Small aircraft", "Helicopter", "Sailboat", "Motorboat",
        ])
    }
}
