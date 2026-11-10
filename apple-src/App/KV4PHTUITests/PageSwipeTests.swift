import XCTest

// A phone only: the Mac has no pages to swipe, and its UI tests no swipes.
#if os(iOS)
    /// The pages of a phone form a ring: a swipe goes from the memories straight to the settings and back.
    @MainActor
    final class PageSwipeTests: XCTestCase {
        private var app: XCUIApplication!

        override func setUp() async throws {
            continueAfterFailure = false
            app = XCUIApplication()
            app.launchArguments = ["-uitest-demo"]
            app.launch()
        }

        func testSwipesFromTheMemoriesToTheSettingsAndBack() throws {
            let memories = app.buttons["page-Memories"]
            guard memories.waitForExistence(timeout: 60) else {
                throw XCTSkip("Only a phone has the page bar")
            }
            XCTAssertTrue(isSelected(memories))
            app.swipeRight()
            XCTAssertTrue(isSelected(app.buttons["page-Settings"]), "A swipe right on the memories shows the settings")
            // The swipe ends on the settings themselves, not on the copy that stands before the memories.
            app.buttons["settings-Radio"].firstMatch.tap()
            XCTAssertTrue(app.navigationBars["Radio"].waitForExistence(timeout: 5), "The settings take a tap")
            app.navigationBars.buttons["Settings"].firstMatch.tap()
            app.swipeLeft()
            XCTAssertTrue(isSelected(memories), "A swipe left on the settings shows the memories")
        }

        func testSwipesBetweenThePagesWhileAPageOfTheSettingsIsOpen() throws {
            let settings = app.buttons["page-Settings"]
            guard settings.waitForExistence(timeout: 60) else {
                throw XCTSkip("Only a phone has the page bar")
            }
            settings.tap()
            let radio = app.buttons["settings-Radio"].firstMatch
            XCTAssertTrue(radio.waitForExistence(timeout: 5))
            radio.tap()
            XCTAssertTrue(app.navigationBars["Radio"].waitForExistence(timeout: 5))
            app.buttons["page-Chats"].tap()
            XCTAssertTrue(isSelected(app.buttons["page-Chats"]))
            app.swipeRight()
            XCTAssertTrue(isSelected(app.buttons["page-Packets"]), "The pages still swipe outside the settings")
        }

        private func isSelected(_ element: XCUIElement) -> Bool {
            let selected = NSPredicate(format: "isSelected == true")
            return XCTWaiter.wait(for: [expectation(for: selected, evaluatedWith: element)], timeout: 5) == .completed
        }
    }
#endif
