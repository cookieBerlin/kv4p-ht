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
        XCTAssertTrue(scrolledTo(row("Calling channel")), "The frequencies did not come")
        chooseLayer("70 cm")
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
        #if os(macOS)
            layers.tapOrClick()
            Thread.sleep(forTimeInterval: 1)
            app.typeText(name)
            app.typeKey(.return, modifierFlags: [])
        #else
            let entry = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
            layers.tap()
            XCTAssertTrue(entry.waitForExistence(timeout: 5), "No \(name) in the layers")
            // The entries of the open menu report no point to tap at times, also once they are on screen, so the middle
            // of the frame is tapped, once the menu has stopped moving.
            var frame = entry.frame
            let deadline = Date.now.addingTimeInterval(3)
            repeat {
                Thread.sleep(forTimeInterval: 0.3)
                let next = entry.frame
                if next == frame { break }
                frame = next
            } while Date.now < deadline
            // The menu closes after a choice, so while it stays open, the tap did not take and is made again; a tap that
            // took cannot be repeated by this. Until it has closed, the list below takes no queries.
            // While the menu comes or goes, the frame of an entry can be infinite, which a tap does not take.
            for _ in 0..<3 where entry.exists {
                let frame = entry.frame
                if !frame.isInfinite, !frame.isEmpty {
                    entry.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                }
                _ = entry.waitForNonExistence(timeout: 5)
            }
            XCTAssertFalse(entry.exists, "The layers stay open")
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
