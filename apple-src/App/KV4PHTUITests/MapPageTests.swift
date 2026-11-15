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
        XCTAssertTrue(app.openMapLayers(), "The layers did not open")
        chooseLayer("Frequencies")
        // The layers stay open after a choice, so that several can be switched at once.
        XCTAssertTrue(layer("Beacons").exists, "The layers closed after a choice")
        XCTAssertTrue(app.closeMapLayers(), "The layers stay open")
        XCTAssertTrue(scrolledTo(row("Calling channel")), "The frequencies did not come")
        XCTAssertTrue(app.openMapLayers(), "The layers did not open")
        chooseLayer("70 cm")
        XCTAssertTrue(app.closeMapLayers(), "The layers stay open")
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

    /// A marker within the part of the map on screen.
    private func onMap(_ marker: XCUIElement) -> Bool {
        let map = app.descendants(matching: .any)["map"].firstMatch
        return marker.exists && map.frame.contains(CGPoint(x: marker.frame.midX, y: marker.frame.midY))
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

    /// Once the app has started, without waiting for the page bar of a phone where there is none.
    private func openMap() {
        XCTAssertTrue(app.waitForStart(), "The app did not start")
        app.showPage("Map")
    }

    /// A switch or a band of the open layers, by the start of its name.
    private func layer(_ name: String) -> XCUIElement {
        app.mapLayersPanel.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", name))
            .matching(
                NSPredicate(
                    format: "elementType IN %@",
                    [
                        XCUIElement.ElementType.switch.rawValue, XCUIElement.ElementType.checkBox.rawValue,
                        XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.radioButton.rawValue,
                    ]
                )
            )
            .firstMatch
    }

    private func chooseLayer(_ name: String) {
        let entry = layer(name)
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "No \(name) in the layers")
        #if os(iOS)
            // A switch of iOS takes a tap on its knob, not on the middle of its row.
            if entry.elementType == .switch {
                entry.switches.firstMatch.exists ? entry.switches.firstMatch.tap() : entry.tap()
                return
            }
        #endif
        entry.tapOrClick()
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
