import XCTest

/// Without a connection, the memories offer it where PTT stands: the choice of radio and *Connect*. Once connected, PTT
/// stands there alone, and *Disconnect* is in the settings (ADR-0075).
@MainActor
final class ConnectionTests: XCTestCase {
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

    func testWithoutAConnectionTheMemoriesOfferIt() {
        // The demo connects to the simulated radio by itself.
        XCTAssertTrue(pushToTalk.waitForExistence(timeout: 60), "No PTT while connected")
        XCTAssertFalse(connectHere.exists, "A connection to make while connected")
        disconnectInSettings()
        XCTAssertTrue(connectHere.waitForExistence(timeout: 10), "No connection where PTT stands")
        XCTAssertFalse(pushToTalk.exists, "PTT without a connection")
        #if os(iOS)
            // The other pages of a phone show the status only.
            let packets = app.buttons["page-Packets"].firstMatch
            if packets.exists {
                packets.tap()
                XCTAssertTrue(connectHere.waitForNonExistence(timeout: 5), "The packets offer the connection")
                app.buttons["page-Memories"].firstMatch.tap()
                XCTAssertTrue(connectHere.waitForExistence(timeout: 5), "The connection does not come back")
            }
        #endif
        connectHere.tapOrClick()
        XCTAssertTrue(pushToTalk.waitForExistence(timeout: 10), "Did not connect")
        XCTAssertFalse(connectHere.exists, "The connection stays after connecting")
    }

    /// A wide window also ends the connection in its header; the Mac's menu connects and disconnects with ⌘K.
    func testAWideWindowDisconnectsInTheHeader() throws {
        XCTAssertTrue(pushToTalk.waitForExistence(timeout: 60), "No PTT while connected")
        guard !app.buttons["page-Memories"].exists else {
            throw XCTSkip("A phone has no room for it")
        }
        let disconnect = app.buttons["Disconnect"].firstMatch
        XCTAssertTrue(disconnect.waitForExistence(timeout: 5), "No way to disconnect in the header")
        disconnect.tapOrClick()
        XCTAssertTrue(connectHere.waitForExistence(timeout: 10), "Did not disconnect")
        #if os(macOS)
            app.typeKey("k", modifierFlags: .command)
            XCTAssertTrue(pushToTalk.waitForExistence(timeout: 10), "⌘K did not connect")
            app.typeKey("k", modifierFlags: .command)
            XCTAssertTrue(connectHere.waitForExistence(timeout: 10), "⌘K did not disconnect")
        #endif
    }

    /// The button of the connection where PTT stands, beside the one in the settings.
    private var connectHere: XCUIElement {
        app.buttons["connection-action"].firstMatch
    }

    /// The PTT button of the main screen; a phone shows only its symbol, with the same name.
    private var pushToTalk: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Push to talk'")).firstMatch
    }

    /// Ends the connection in the settings and closes them: a phone goes back to the memories page, an iPad goes back
    /// to the main screen, and the Mac closes its settings window.
    private func disconnectInSettings() {
        app.openSettings()
        #if os(macOS)
            app.openSettingsPage("Radio")
        #endif
        let disconnect = app.buttons["Disconnect"].firstMatch
        XCTAssertTrue(disconnect.waitForExistence(timeout: 5), "The settings do not offer to disconnect")
        disconnect.tapOrClick()
        XCTAssertTrue(app.buttons["Connect"].firstMatch.waitForExistence(timeout: 10), "Did not disconnect")
        #if os(macOS)
            app.typeKey("w", modifierFlags: .command)
        #else
            let memories = app.buttons["page-Memories"]
            if memories.exists {
                memories.tap()
            } else {
                app.goBack()
            }
        #endif
    }
}
