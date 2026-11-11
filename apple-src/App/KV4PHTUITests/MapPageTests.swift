import XCTest

/// The map shows the memories with a position, also as a list, by layer and band, and it can be switched off
/// (ADR-0068).
@MainActor
final class MapPageTests: XCTestCase {
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
    }

    func testTheMapShowsTheMemoriesWithAPositionByLayerAndBand() {
        openMap()
        XCTAssertTrue(element("Local repeater").waitForExistence(timeout: 30), "No repeater on the map")
        choose("List")
        XCTAssertTrue(row("Local repeater").waitForExistence(timeout: 5), "No repeater in the list")
        XCTAssertTrue(row("Local beacon").exists, "No beacon in the list")
        XCTAssertFalse(row("Calling channel").exists, "The frequencies are on by default")
        chooseLayer("Frequencies")
        XCTAssertTrue(row("Calling channel").waitForExistence(timeout: 5), "The frequencies did not come")
        chooseLayer("70 cm")
        XCTAssertTrue(row("Local repeater").waitForNonExistence(timeout: 5), "The 2 m repeater is still there")
    }

    func testAStationLeadsToItsPackets() {
        openMap()
        choose("List")
        let station = app.descendants(matching: .any)["map-list"].descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'N1CALL, '")).firstMatch
        XCTAssertTrue(station.waitForExistence(timeout: 30), "No station in the list")
        station.tapOrClick()
        // The page bar of a phone, or the switch beside the memories elsewhere, whose chosen part the Mac marks by its
        // value.
        #if os(macOS)
            let packets = app.radioButtons.matching(NSPredicate(format: "label BEGINSWITH 'Packets' AND value == 1"))
                .firstMatch
        #else
            let packets = app.descendants(matching: .any).matching(
                NSPredicate(
                    format: "(identifier == 'page-Packets' OR label BEGINSWITH 'Packets') AND isSelected == true"
                )
            ).firstMatch
        #endif
        XCTAssertTrue(packets.waitForExistence(timeout: 5), "The packets are not shown")
    }

    func testSwitchingTheMapOffHidesIt() {
        XCTAssertTrue(mapPage.waitForExistence(timeout: 30), "No map to begin with")
        app.openSettings()
        app.openSettingsPage("Pages")
        app.flip("toggle-Map")
        app.goBack()
        app.goBack()
        XCTAssertTrue(mapPage.waitForNonExistence(timeout: 5), "The map is still there")
    }

    /// The page bar of a phone, or the switch beside the memories elsewhere; the switch in the settings is no button.
    private var mapPage: XCUIElement {
        #if os(macOS)
            app.radioButtons["Map"].firstMatch
        #else
            app.buttons.matching(NSPredicate(format: "identifier == 'page-Map' OR label == 'Map'")).firstMatch
        #endif
    }

    private func openMap() {
        let page = app.buttons["page-Map"].firstMatch
        if page.waitForExistence(timeout: 30) {
            page.tap()
        } else {
            choose("Map")
        }
    }

    /// An entry of the menu of the layers, by the start of its name. The Mac shows the menu, but XCTest does not see its
    /// entries while it is open, so they are chosen by typing, as a menu of the Mac offers.
    private func chooseLayer(_ name: String) {
        let layers = app.descendants(matching: .any)["map-layers"].firstMatch
        XCTAssertTrue(layers.waitForExistence(timeout: 5), "No layers")
        layers.tapOrClick()
        #if os(macOS)
            Thread.sleep(forTimeInterval: 1)
            app.typeText(name)
            app.typeKey(.return, modifierFlags: [])
        #else
            let entry = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
            XCTAssertTrue(entry.waitForExistence(timeout: 5), "No \(name) in the layers")
            entry.tap()
        #endif
    }

    /// A part of a segmented switch: buttons on iPhone and iPad, radio buttons on the Mac.
    private func choose(_ label: String) {
        #if os(macOS)
            let part = app.radioButtons[label].firstMatch
        #else
            let part =
                app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != 'page-Map'", label))
                .allElementsBoundByIndex.first(where: \.isHittable) ?? app.buttons[label].firstMatch
        #endif
        XCTAssertTrue(part.waitForExistence(timeout: 30), "No \(label) to choose")
        part.tapOrClick()
    }

    private func element(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// A row of the list reads the kind first, where it has one, then the name.
    private func row(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)["map-list"].descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@ OR label CONTAINS %@", "\(name), ", ", \(name), "))
            .firstMatch
    }
}
