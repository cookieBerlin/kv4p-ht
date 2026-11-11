import XCTest

/// APRS can be switched off in the settings, and then its pages go (ADR-0066).
@MainActor
final class PagesSettingTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        connectToWindowServer()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest-demo"]
        app.launch()
    }

    func testSwitchingAPRSOffHidesItsPages() {
        #if os(macOS)
            app.closeAbout()
        #endif
        XCTAssertTrue(aprsPages.firstMatch.waitForExistence(timeout: 60), "No packets or chats to begin with")
        openSettings()
        let pages = app.descendants(matching: .any)["settings-Pages"].firstMatch
        XCTAssertTrue(pages.waitForExistence(timeout: 5), "No page for the pages in the settings")
        // An iPad pushes the settings onto the main page; a tap while they move in goes astray.
        let hittable = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: pages)
        XCTAssertEqual(
            XCTWaiter.wait(for: [hittable], timeout: 5),
            .completed,
            "The page for the pages cannot be tapped"
        )
        Thread.sleep(forTimeInterval: 1)
        #if os(macOS)
            pages.click()
        #else
            pages.tap()
        #endif
        let toggle = app.descendants(matching: .any)["toggle-APRS"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "No switch for APRS")
        #if os(macOS)
            toggle.click()
        #else
            toggle.switches.firstMatch.tap()
        #endif
        goBack()
        let aprsSettings = app.descendants(matching: .any)["settings-APRS"].firstMatch
        XCTAssertTrue(app.descendants(matching: .any)["settings-Pages"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(aprsSettings.exists, "The settings still offer APRS")
        // On an iPad, the settings stand in front of the main page; a phone has all pages there at once.
        goBack()
        // The page bar of a phone, or PTT on the main page elsewhere.
        let main = app.buttons.matching(NSPredicate(format: "identifier == 'page-Memories' OR label == 'Push to talk'"))
        XCTAssertTrue(main.firstMatch.waitForExistence(timeout: 5), "The main page is not there")
        XCTAssertTrue(aprsPages.firstMatch.waitForNonExistence(timeout: 5), "The packets or chats are still there")
    }

    /// The page bar of a phone, or the switch between the packets and the chats elsewhere.
    private var aprsPages: XCUIElementQuery {
        app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier == 'page-Packets' OR identifier == 'page-Chats' OR label BEGINSWITH 'Packets' "
                    + "OR label BEGINSWITH 'Chats'"
            )
        )
    }

    /// iPhone and iPad: one page back; the Mac shows the settings in a window of their own.
    private func goBack() {
        #if os(iOS)
            // A phone has its other pages beside the one on screen, with their own bars.
            let backs = app.navigationBars.buttons.matching(identifier: "BackButton").allElementsBoundByIndex
            if let back = backs.first(where: \.isHittable) {
                back.tap()
                Thread.sleep(forTimeInterval: 1)
            }
        #endif
    }

    private func openSettings() {
        #if os(macOS)
            app.typeKey(",", modifierFlags: .command)
        #else
            let page = app.buttons["page-Settings"]
            if page.exists { page.tap() } else { app.buttons["Settings"].firstMatch.tap() }
        #endif
    }
}
