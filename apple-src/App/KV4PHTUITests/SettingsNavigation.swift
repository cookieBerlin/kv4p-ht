import XCTest

extension XCUIApplication {
    /// The settings window of the Mac, the page of a phone or the screen an iPad pushes onto the main page.
    func openSettings() {
        #if os(macOS)
            typeKey(",", modifierFlags: .command)
        #else
            let page = buttons["page-Settings"]
            if page.exists { page.tap() } else { buttons["Settings"].firstMatch.tap() }
        #endif
    }

    /// A page from the list of the settings, once it can be reached: an iPad pushes the settings onto the main page,
    /// and a tap while they move in goes astray.
    func openSettingsPage(_ name: String) {
        let page = descendants(matching: .any)["settings-\(name)"].firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 5), "No page \(name) in the settings")
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: page)
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 5), .completed, "The page \(name) cannot be tapped")
        Thread.sleep(forTimeInterval: 1)
        page.tapOrClick()
    }

    /// iPhone and iPad: one page back; the Mac shows the settings in a window of their own.
    func goBack() {
        #if os(iOS)
            // A phone has its other pages beside the one on screen, with their own bars.
            let backs = navigationBars.buttons.matching(identifier: "BackButton").allElementsBoundByIndex
            if let back = backs.first(where: \.isHittable) {
                back.tap()
                Thread.sleep(forTimeInterval: 1)
            }
        #endif
    }

    /// A switch of the settings, by its identifier.
    func flip(_ identifier: String) {
        let toggle = descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "No switch \(identifier)")
        #if os(macOS)
            toggle.click()
        #else
            toggle.switches.firstMatch.tap()
        #endif
    }
}

extension XCUIElement {
    func tapOrClick() {
        #if os(macOS)
            click()
        #else
            tap()
        #endif
    }
}
