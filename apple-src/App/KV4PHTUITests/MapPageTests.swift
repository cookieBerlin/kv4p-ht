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
        app.launchArguments = XCUIApplication.demoArguments
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
        XCTAssertTrue(app.openPanel("map-layers"), "The layers did not open")
        app.choosePanelEntry("map-layers", "Frequencies")
        // The layers stay open after a choice, so that several can be switched at once.
        XCTAssertTrue(app.panelEntry("map-layers", "Beacons").exists, "The layers closed after a choice")
        XCTAssertTrue(app.closePanel("map-layers"), "The layers stay open")
        XCTAssertTrue(scrolledTo(row("Calling channel")), "The frequencies did not come")
        XCTAssertTrue(app.openPanel("map-layers"), "The layers did not open")
        app.choosePanelEntry("map-layers", "70 cm")
        XCTAssertTrue(app.closePanel("map-layers"), "The layers stay open")
        XCTAssertTrue(row("Local repeater").waitForNonExistence(timeout: 5), "The 2 m repeater is still there")
    }

    func testShowAllBringsBackEveryMarker() {
        openMap()
        let repeater = element("Local repeater")
        XCTAssertTrue(repeater.waitForExistence(timeout: 30), "No repeater on the map")
        let map = app.descendants(matching: .any)["map"].firstMatch
        // Far away, so that no marker is left on screen; a swipe flings the map further than a drag.
        for _ in 0..<6 where onMap(repeater) {
            #if os(macOS)
                drag(map, from: CGVector(dx: 0.1, dy: 0.5), to: CGVector(dx: 0.9, dy: 0.5))
            #else
                map.swipeRight(velocity: .fast)
            #endif
        }
        XCTAssertFalse(onMap(repeater), "The map did not move")
        let showAll = app.descendants(matching: .any)["map-show-all"].firstMatch
        XCTAssertTrue(showAll.waitForExistence(timeout: 5), "No button to show all")
        showAll.tapOrClick()
        let deadline = Date.now.addingTimeInterval(5)
        while !onMap(repeater), Date.now < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(onMap(repeater), "The repeater did not come back")
        XCTAssertTrue(onMap(element("Local beacon")), "The beacon did not come back")
    }

    /// A marker within the part of the map on screen. Read once, by a snapshot: MapKit draws its markers anew, and one
    /// that goes between asking whether it is there and asking where would fail the test.
    private func onMap(_ marker: XCUIElement) -> Bool {
        let map = app.descendants(matching: .any)["map"].firstMatch
        guard let frame = try? marker.snapshot().frame, let mapFrame = try? map.snapshot().frame else { return false }
        return mapFrame.contains(CGPoint(x: frame.midX, y: frame.midY))
    }

    private func drag(_ element: XCUIElement, from start: CGVector, to end: CGVector) {
        let from = element.coordinate(withNormalizedOffset: start)
        let to = element.coordinate(withNormalizedOffset: end)
        #if os(macOS)
            from.click(forDuration: 0.1, thenDragTo: to)
        #else
            from.press(forDuration: 0.1, thenDragTo: to)
        #endif
    }

    func testAStationLeadsToItsPackets() {
        openMap()
        choose("List")
        let station = app.descendants(matching: .any)["map-list"].descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'N1CALL, '")).firstMatch
        XCTAssertTrue(scrolledTo(station), "No station in the list")
        station.tapOrClick()
        // The page bar of a phone, or the switch beside the memories elsewhere.
        let packets = app.descendants(matching: .any).matching(
            NSPredicate(format: "(identifier == 'page-Packets' OR label BEGINSWITH 'Packets') AND isSelected == true")
        ).firstMatch
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
        app.buttons.matching(NSPredicate(format: "identifier == 'page-Map' OR label == 'Map'")).firstMatch
    }

    /// Once the app has started, without waiting for the page bar of a phone where there is none.
    private func openMap() {
        XCTAssertTrue(app.waitForStart(), "The app did not start")
        app.showPage("Map")
    }

    /// A part of the switch between map and list: a button each, beside the page of the map on a phone.
    private func choose(_ label: String) {
        let part =
            app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != 'page-Map'", label))
            .allElementsBoundByIndex.first(where: \.isHittable) ?? app.buttons[label].firstMatch
        XCTAssertTrue(part.waitForExistence(timeout: 30), "No \(label) to choose")
        XCTAssertTrue(part.waitForHittable(timeout: 10), "\(label) cannot be chosen")
        part.tapOrClick()
    }

    /// A marker of the map. Within the map only: a query of the whole app, with the map in it, takes so long on a busy
    /// machine that XCTest gives it up.
    private func element(_ label: String) -> XCUIElement {
        app.descendants(matching: .any)["map"].firstMatch.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// A row of the list, scrolled to: the list makes its rows as they come on screen, and on a low screen the
    /// stations stand below the memories.
    private func scrolledTo(_ row: XCUIElement) -> Bool {
        let list = app.descendants(matching: .any)["map-list"].firstMatch
        guard list.waitForExistence(timeout: 30) else { return false }
        for _ in 0..<6 {
            if row.waitForExistence(timeout: 2), row.isHittable { return true }
            #if os(macOS)
                list.scroll(byDeltaX: 0, deltaY: -200)
            #else
                list.swipeUp()
            #endif
        }
        return row.exists && row.isHittable
    }

    /// A row of the list reads the kind first, where it has one, then the name.
    private func row(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)["map-list"].descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@ OR label CONTAINS %@", "\(name), ", ", \(name), "))
            .firstMatch
    }
}
