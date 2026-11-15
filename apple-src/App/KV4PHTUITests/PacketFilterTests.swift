import XCTest

/// The filter above the packets: a callsign, which a button clears, and the types, in a panel that stays open.
@MainActor
final class PacketFilterTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        connectToWindowServer()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest-demo"]
        app.launch()
        #if os(macOS)
            app.closeAbout()
        #endif
        XCTAssertTrue(app.waitForStart(), "The app did not start")
        app.showPage("Packets")
    }

    func testClearEmptiesTheCallsign() {
        let field = app.textFields.matching(
            NSPredicate(format: "label == 'Callsign' OR placeholderValue == 'Callsign'")
        )
        .firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "No callsign to filter by")
        let clear = app.buttons["Clear"].firstMatch
        XCTAssertFalse(clear.exists, "A button clears an empty callsign")
        field.tapOrClick()
        field.typeText("N1CALL")
        XCTAssertTrue(clear.waitForExistence(timeout: 5), "No button clears the callsign")
        clear.tapOrClick()
        // Empty on the Mac; iOS reads the prompt of an empty field as its value.
        let value = field.value as? String ?? ""
        XCTAssertTrue(value.isEmpty || value == field.placeholderValue, "The callsign is still there")
        XCTAssertTrue(clear.waitForNonExistence(timeout: 5), "The button stays without a callsign")
    }

    func testTheTypesStayOpenAfterAChoice() {
        XCTAssertTrue(app.openPanel("packet-types"), "The types did not open")
        app.choosePanelEntry("packet-types", "Messages")
        XCTAssertTrue(app.panelEntry("packet-types", "Positions").exists, "The types closed after a choice")
        app.choosePanelEntry("packet-types", "Messages")
        XCTAssertTrue(app.closePanel("packet-types"), "The types stay open")
    }
}
