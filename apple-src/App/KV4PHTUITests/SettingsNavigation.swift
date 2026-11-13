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
    /// and a phone scrolls them in from the side; a tap while they move goes astray. The phone also has copies of its
    /// pages beside the ring, so the one that can be tapped is taken.
    func openSettingsPage(_ name: String) {
        let links = descendants(matching: .any).matching(identifier: "settings-\(name)")
        XCTAssertTrue(links.firstMatch.waitForExistence(timeout: 5), "No page \(name) in the settings")
        let deadline = Date.now.addingTimeInterval(15)
        var link = links.allElementsBoundByIndex.first(where: \.isHittable)
        while link == nil, Date.now < deadline {
            Thread.sleep(forTimeInterval: 0.5)
            link = links.allElementsBoundByIndex.first(where: \.isHittable)
        }
        guard let link else { return XCTFail("The page \(name) cannot be tapped") }
        Thread.sleep(forTimeInterval: 1)
        link.tapOrClick()
    }

    /// iPhone and iPad: one page back; the Mac shows the settings in a window of their own.
    func goBack() {
        #if os(iOS)
            // A phone has its other pages beside the one on screen, with their own bars. Where the system puts the
            // toolbar at the side, as an open iPhone Duo does, the button is not within the navigation bar.
            let backs = buttons.matching(identifier: "BackButton").allElementsBoundByIndex
            if let back = backs.first(where: \.isHittable) {
                back.tap()
                Thread.sleep(forTimeInterval: 1)
            }
        #endif
    }

    /// A switch of the settings, by its identifier, once it can be reached; a tap while its page moves in goes astray,
    /// so it is tapped again until the switch has changed.
    func flip(_ identifier: String) {
        let toggle = descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "No switch \(identifier)")
        #if os(macOS)
            let control = toggle
        #else
            let control = toggle.switches.firstMatch
        #endif
        // A number on iPhone and iPad, so compared as text.
        let before = String(describing: control.value)
        for _ in 0..<3 {
            let hittable = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "isHittable == true"),
                object: control
            )
            _ = XCTWaiter.wait(for: [hittable], timeout: 5)
            control.tapOrClick()
            // The page of the switch may be built anew when it changes what pages there are.
            let deadline = Date.now.addingTimeInterval(2)
            while Date.now < deadline {
                if !control.exists || String(describing: control.value) != before { return }
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
        XCTFail("The switch \(identifier) did not change")
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
