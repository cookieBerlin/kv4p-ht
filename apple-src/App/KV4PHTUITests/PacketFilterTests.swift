import XCTest

/// The filter of the packets, in a panel that a button floating over the list opens: a callsign, which a button
/// clears, *For me* and the types. While it is on, a line above the list says so and clears it.
@MainActor
final class PacketFilterTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        connectToWindowServer()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = XCUIApplication.demoArguments
        app.launch()
        #if os(macOS)
            app.closeAbout()
        #endif
        XCTAssertTrue(app.waitForStart(), "The app did not start")
        app.showPage("Packets")
    }

    private var field: XCUIElement {
        app.panel("packet-filter").textFields
            .matching(NSPredicate(format: "label == 'Callsign' OR placeholderValue == 'Callsign'")).firstMatch
    }

    private var notice: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "filter-notice")
            .allElementsBoundByIndex.first(where: \.isHittable) ?? app.descendants(matching: .any)["filter-notice"]
    }

    private func typeCallsign(_ callsign: String) {
        XCTAssertTrue(app.openPanel("packet-filter"), "The filter did not open")
        XCTAssertTrue(field.waitForExistence(timeout: 5), "No callsign to filter by")
        field.tapOrClick()
        field.typeText(callsign)
    }

    func testClearEmptiesTheCallsign() {
        XCTAssertTrue(app.openPanel("packet-filter"), "The filter did not open")
        let clear = app.panel("packet-filter").buttons["Clear"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "No callsign to filter by")
        XCTAssertFalse(clear.exists, "A button clears an empty callsign")
        field.tapOrClick()
        field.typeText("N1CALL")
        XCTAssertTrue(clear.waitForExistence(timeout: 5), "No button clears the callsign")
        clear.tapOrClick()
        // Empty on the Mac; iOS reads the prompt of an empty field as its value.
        let value = field.value as? String ?? ""
        XCTAssertTrue(value.isEmpty || value == field.placeholderValue, "The callsign is still there")
        XCTAssertTrue(clear.waitForNonExistence(timeout: 5), "The button stays without a callsign")
        XCTAssertTrue(app.closePanel("packet-filter"), "The filter stays open")
    }

    func testTheTypesStayOpenAfterAChoice() {
        XCTAssertTrue(app.openPanel("packet-filter"), "The filter did not open")
        app.choosePanelEntry("packet-filter", "Messages")
        XCTAssertTrue(app.panelEntry("packet-filter", "Positions").exists, "The filter closed after a choice")
        app.choosePanelEntry("packet-filter", "Messages")
        XCTAssertTrue(app.closePanel("packet-filter"), "The filter stays open")
    }

    func testALineAboveTheListShowsTheFilterAndClearsIt() {
        XCTAssertFalse(notice.exists, "A line shows a filter that is off")
        typeCallsign("N1CALL")
        XCTAssertTrue(app.closePanel("packet-filter"), "The filter stays open")
        XCTAssertTrue(notice.waitForExistence(timeout: 5), "No line shows the filter")
        XCTAssertTrue(notice.label.contains("N1CALL"), "The line does not name the callsign: \(notice.label)")
        let clear = notice.buttons["Clear filter"].firstMatch
        XCTAssertTrue(clear.exists, "The line cannot clear the filter")
        clear.tapOrClick()
        XCTAssertTrue(notice.waitForNonExistence(timeout: 5), "The line stays after clearing the filter")
    }
}
