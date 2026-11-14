import XCTest

extension XCUIApplication {
    /// The page bar on a phone, or PTT elsewhere, whatever the text size.
    func waitForStart() -> Bool {
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            if buttons["page-Memories"].exists || buttons["Push to talk"].exists {
                return true
            }
            Thread.sleep(forTimeInterval: 1)
        }
        return false
    }

    /// The page bar of a phone; elsewhere the memories stand beside a switch between the packets, the chats and the
    /// map, and the settings open from the toolbar.
    func showPage(_ title: String) {
        let pageButton = buttons["page-\(title)"].firstMatch
        if !pageButton.exists, ["Packets", "Chats", "Map"].contains(title) {
            // With unread messages, the switch says how many, as "Chats (2)". The Mac shows its parts as radio buttons.
            let part = NSPredicate(format: "label BEGINSWITH %@", title)
            #if os(macOS)
                radioButtons.matching(part).firstMatch.click()
            #else
                buttons.matching(part).firstMatch.tap()
            #endif
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
}
