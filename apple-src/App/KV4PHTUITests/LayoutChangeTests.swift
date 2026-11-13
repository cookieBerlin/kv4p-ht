import XCTest

// iPhone and iPad only: the Mac has one layout.
#if os(iOS)
    /// A foldable iPhone changes between the compact and the wide layout while the app runs. A large iPhone does the
    /// same when it turns, which these tests use: what was written and the settings that were open stay.
    @MainActor
    final class LayoutChangeTests: XCTestCase {
        private var app: XCUIApplication!

        override func setUp() async throws {
            continueAfterFailure = false
            XCUIDevice.shared.orientation = .portrait
            app = XCUIApplication()
            app.launchArguments = ["-uitest-demo"]
            app.launch()
        }

        override func tearDown() async throws {
            XCUIDevice.shared.orientation = .portrait
        }

        func testADraftStaysWhenTheLayoutChanges() throws {
            try requireLayoutChange()
            app.buttons["page-Packets"].tap()
            let field = messageField
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText("Hello")
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(
                messageField.waitForValue("Hello"),
                "The wide layout lost the draft"
            )
            XCUIDevice.shared.orientation = .portrait
            XCTAssertTrue(messageField.waitForValue("Hello"), "The compact layout lost the draft")
        }

        func testOpenSettingsStayOpenWhenTheLayoutChanges() throws {
            try requireLayoutChange()
            app.openSettings()
            app.openSettingsPage("Radio")
            XCTAssertTrue(app.navigationBars["Radio"].waitForExistence(timeout: 5))
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(app.buttons["page-Memories"].waitForNonExistence(timeout: 10), "Still the compact layout")
            XCTAssertTrue(app.navigationBars["Radio"].waitForExistence(timeout: 5), "The wide layout closed the page")
            XCUIDevice.shared.orientation = .portrait
            XCTAssertTrue(app.buttons["page-Settings"].waitForExistence(timeout: 10))
            XCTAssertTrue(
                app.navigationBars["Radio"].waitForExistence(timeout: 5),
                "The compact layout closed the page"
            )
        }

        /// Only a device whose width class changes as it turns, such as a large iPhone, changes the layout.
        private func requireLayoutChange() throws {
            guard app.buttons["page-Memories"].waitForExistence(timeout: 60) else {
                throw XCTSkip("Starts in the wide layout")
            }
            XCUIDevice.shared.orientation = .landscapeLeft
            let changes = app.buttons["page-Memories"].waitForNonExistence(timeout: 10)
            XCUIDevice.shared.orientation = .portrait
            guard changes else { throw XCTSkip("Keeps the compact layout when turned") }
            XCTAssertTrue(app.buttons["page-Memories"].waitForExistence(timeout: 10))
        }

        /// The line to write of the packets; a phone has copies of its pages beside the ring.
        private var messageField: XCUIElement {
            let fields = app.textFields.matching(identifier: "Message").allElementsBoundByIndex
            return fields.first(where: \.isHittable) ?? app.textFields["Message"].firstMatch
        }
    }

    extension XCUIElement {
        /// Whether the element shows the text within the time.
        fileprivate func waitForValue(_ text: String, timeout: TimeInterval = 10) -> Bool {
            let deadline = Date.now.addingTimeInterval(timeout)
            repeat {
                if exists, (value as? String) == text { return true }
                Thread.sleep(forTimeInterval: 0.3)
            } while Date.now < deadline
            return false
        }
    }
#endif
