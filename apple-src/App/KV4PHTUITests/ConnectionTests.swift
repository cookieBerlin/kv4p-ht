import XCTest

// iPhone and iPad only: the Mac connects in the main window.
#if os(iOS)
    /// iPhone and iPad choose and connect the radio in the settings; without a connection, the main screen leads
    /// there instead of offering PTT (ADR-0071).
    @MainActor
    final class ConnectionTests: XCTestCase {
        private var app: XCUIApplication!

        override func setUp() async throws {
            continueAfterFailure = false
            app = XCUIApplication()
            app.launchArguments = ["-uitest-demo"]
            app.launch()
        }

        func testWithoutAConnectionTheMainScreenLeadsToTheSettings() {
            // The demo connects to the simulated radio by itself.
            XCTAssertTrue(pushToTalk.waitForExistence(timeout: 60), "No PTT while connected")
            app.openSettings()
            let disconnect = app.buttons["Disconnect"].firstMatch
            XCTAssertTrue(disconnect.waitForExistence(timeout: 5), "The settings do not offer the connection")
            disconnect.tap()
            XCTAssertTrue(app.buttons["Connect"].firstMatch.waitForExistence(timeout: 10))
            closeSettings()
            // The status and the way to the settings are one button.
            let connectInSettings = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Connect in Settings'"))
                .firstMatch
            XCTAssertTrue(connectInSettings.waitForExistence(timeout: 10), "No way to the settings")
            XCTAssertFalse(pushToTalk.exists, "PTT without a connection")
            connectInSettings.tap()
            let connect = app.buttons["Connect"].firstMatch
            XCTAssertTrue(connect.waitForExistence(timeout: 5), "The way does not lead to the connection")
            connect.tap()
            XCTAssertTrue(app.buttons["Disconnect"].firstMatch.waitForExistence(timeout: 10), "Did not connect")
        }

        /// The PTT button of the main screen; a phone shows only its symbol, with the same name.
        private var pushToTalk: XCUIElement {
            app.buttons.matching(NSPredicate(format: "label == 'Push to talk'")).firstMatch
        }

        /// A phone goes back to the memories page; elsewhere the settings stand on top of the main screen.
        private func closeSettings() {
            let memories = app.buttons["page-Memories"]
            if memories.exists {
                memories.tap()
            } else {
                app.goBack()
            }
        }
    }
#endif
