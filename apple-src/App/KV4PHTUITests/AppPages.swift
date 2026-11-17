import XCTest

extension XCUIApplication {
    /// How the UI tests start the app: in the demo mode, with the small demo's lists (ADR-0076). With the lists of a day
    /// on air, reading a screen runs out of time on a busy machine. The screenshots start with the whole demo instead.
    static let demoArguments = ["-uitest-demo", "-uitest-small-demo"]

    /// The page bar on a phone, or PTT elsewhere, whatever the text size. On the Mac, the windows of the last run come back, which may be none at all; then a new one opens. After a
    /// crash, macOS first asks whether to reopen them, which keeps the app disabled until it is answered.
    func waitForStart() -> Bool {
        #if os(macOS)
            // "Don't Reopen", by its identifier, as its title follows the language of the Mac.
            // The window or the question, whichever comes first: the question comes only after a crash, so waiting for it
            // alone would cost every start its time.
            let dontReopen = dialogs.buttons["action-button--999"].firstMatch
            let windowDeadline = Date().addingTimeInterval(10)
            var hasWindow = false
            while !hasWindow, Date() < windowDeadline {
                if dontReopen.exists {
                    dontReopen.click()
                }
                hasWindow = windows.firstMatch.exists
                if !hasWindow { Thread.sleep(forTimeInterval: 0.2) }
            }
            if !hasWindow {
                typeKey("n", modifierFlags: .command)
            }
        #endif
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            if buttons["page-Memories"].firstMatch.exists || buttons["Push to talk"].firstMatch.exists {
                return true
            }
            Thread.sleep(forTimeInterval: 1)
        }
        return false
    }

    /// Whether the app shows the page bar of a phone, once it has started: a wide window or the Mac never does, so
    /// waiting for it there only costs the time of the wait.
    var hasPageBar: Bool {
        buttons["page-Memories"].firstMatch.exists
    }

    /// The page bar of a phone; elsewhere the memories stand beside a switch between the packets, the chats and the
    /// map, and the settings open from the toolbar.
    func showPage(_ title: String) {
        let pageButton = buttons["page-\(title)"].firstMatch
        if !pageButton.exists, ["Packets", "Chats", "Map"].contains(title) {
            // With unread messages, the switch says how many, as "Chats (2)".
            buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch.tapOrClick()
        } else if pageButton.exists {
            pageButton.tap()
            // The pages scroll into place; a look before that sees two halves.
            let selected = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "isSelected == true"),
                object: pageButton
            )
            _ = XCTWaiter.wait(for: [selected], timeout: 5)
            Thread.sleep(forTimeInterval: 1)
        } else if title == "Settings" {
            #if os(macOS)
                typeKey(",", modifierFlags: .command)
            #else
                buttons["Settings"].firstMatch.tap()
            #endif
        }
    }

    /// A panel of choices, such as the layers of the map or the types of packets, by the identifier of its button: a
    /// popover, which a phone shows as a sheet. Whether it opened.
    func openPanel(_ identifier: String) -> Bool {
        // The settings show the packets once more, on a page beside it on a phone; the one that can be tapped is taken.
        let buttons = descendants(matching: .any).matching(identifier: identifier)
        guard buttons.firstMatch.waitForExistence(timeout: 5),
            let button = buttons.allElementsBoundByIndex.first(where: \.isHittable)
        else { return false }
        button.tapOrClick()
        return panel(identifier).waitForExistence(timeout: 5)
    }

    func panel(_ identifier: String) -> XCUIElement {
        descendants(matching: .any)["\(identifier)-panel"].firstMatch
    }

    /// Done on iPhone and iPad; the Mac closes a popover with Esc. Whether it closed.
    func closePanel(_ identifier: String) -> Bool {
        #if os(macOS)
            typeKey(.escape, modifierFlags: [])
        #else
            buttons["\(identifier)-done"].firstMatch.tap()
        #endif
        return panel(identifier).waitForNonExistence(timeout: 5)
    }

    /// An entry of an open panel, a switch, checkbox or choice, by the start of its name. The Mac names a choice after
    /// its picker, as "Band, 70 cm".
    func panelEntry(_ identifier: String, _ name: String) -> XCUIElement {
        panel(identifier).descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@ OR label ENDSWITH %@", name, ", \(name)"))
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

    /// Switches or chooses an entry of an open panel.
    func choosePanelEntry(_ identifier: String, _ name: String) {
        let entry = panelEntry(identifier, name)
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "No \(name) in \(identifier)")
        // The panel may still slide in, on a busy machine for seconds.
        XCTAssertTrue(entry.waitForHittable(timeout: 10), "\(name) in \(identifier) cannot be tapped")
        #if os(macOS)
            // A radio button of the Mac reaches across the row, and only its circle and its name take a click.
            if entry.elementType == .radioButton {
                entry.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5)).click()
                return
            }
        #else
            // A switch of iOS takes a tap on its knob, not on the middle of its row.
            if entry.elementType == .switch, entry.switches.firstMatch.exists {
                entry.switches.firstMatch.tap()
                return
            }
        #endif
        entry.tapOrClick()
    }
}
