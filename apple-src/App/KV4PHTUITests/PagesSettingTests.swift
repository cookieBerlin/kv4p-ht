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
        app.openSettings()
        app.openSettingsPage("Pages")
        app.flip("toggle-APRS")
        app.goBack()
        let aprsSettings = app.descendants(matching: .any)["settings-APRS"].firstMatch
        XCTAssertTrue(app.descendants(matching: .any)["settings-Pages"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(aprsSettings.exists, "The settings still offer APRS")
        // On an iPad, the settings stand in front of the main page; a phone has all pages there at once.
        app.goBack()
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
}
