import XCTest

// A phone only: the Mac has no pages to swipe, and its UI tests no swipes.
#if os(iOS)
    /// The pages of a phone form a ring: a swipe goes from the memories straight to the settings and back.
    /// Each query takes its first match: without it, XCTest reads all of the screen to be sure there is only one, which
    /// on a busy machine, while a page moves, runs out of the time it has.
    @MainActor
    final class PageSwipeTests: XCTestCase {
        private var app: XCUIApplication!

        override func setUp() async throws {
            continueAfterFailure = false
            app = XCUIApplication()
            app.launchArguments = XCUIApplication.demoArguments
            app.launch()
        }

        func testSwipesFromTheMemoriesToTheSettingsAndBack() throws {
            XCTAssertTrue(app.waitForStart(), "The app did not start")
            let memories = app.buttons["page-Memories"].firstMatch
            guard app.hasPageBar else {
                throw XCTSkip("Only a phone has the page bar")
            }
            XCTAssertTrue(isSelected(memories))
            app.swipeRight()
            XCTAssertTrue(
                isSelected(app.buttons["page-Settings"].firstMatch),
                "A swipe right on the memories shows the settings"
            )
            // The swipe ends on the settings themselves, not on the copy that stands before the memories.
            app.buttons["settings-Radio"].firstMatch.tap()
            XCTAssertTrue(
                app.navigationBars["Radio"].firstMatch.waitForExistence(timeout: 5),
                "The settings take a tap"
            )
            app.navigationBars.buttons["Settings"].firstMatch.tap()
            app.swipeLeft()
            XCTAssertTrue(isSelected(memories), "A swipe left on the settings shows the memories")
        }

        func testSwipesBetweenThePagesWhileAPageOfTheSettingsIsOpen() throws {
            XCTAssertTrue(app.waitForStart(), "The app did not start")
            let settings = app.buttons["page-Settings"].firstMatch
            guard app.hasPageBar else {
                throw XCTSkip("Only a phone has the page bar")
            }
            settings.tap()
            let radio = app.buttons["settings-Radio"].firstMatch
            XCTAssertTrue(radio.waitForExistence(timeout: 5))
            radio.tap()
            XCTAssertTrue(app.navigationBars["Radio"].firstMatch.waitForExistence(timeout: 5))
            app.buttons["page-Chats"].firstMatch.tap()
            XCTAssertTrue(isSelected(app.buttons["page-Chats"].firstMatch))
            app.swipeRight()
            XCTAssertTrue(
                isSelected(app.buttons["page-Packets"].firstMatch),
                "The pages still swipe outside the settings"
            )
        }

        func testThePagesBesideTheOneShownAreOutOfReach() throws {
            XCTAssertTrue(app.waitForStart(), "The app did not start")
            guard app.hasPageBar else {
                throw XCTSkip("Only a phone has the page bar")
            }
            // The line to write an APRS message stands on the packets, beside the memories.
            let isMessage = NSPredicate(format: "label == 'Message' OR placeholderValue == 'Message'")
            let message = app.textFields.matching(isMessage).firstMatch
            XCTAssertTrue(app.buttons["Push to talk"].firstMatch.waitForExistence(timeout: 60), "Not connected")
            XCTAssertFalse(message.exists, "The packets beside the memories are in reach")
            app.buttons["page-Packets"].firstMatch.tap()
            XCTAssertTrue(message.waitForExistence(timeout: 5), "The packets shown are out of reach")
        }

        /// Waits long enough for a busy machine, where a single look at the page bar can take seconds.
        private func isSelected(_ element: XCUIElement) -> Bool {
            let selected = NSPredicate(format: "isSelected == true")
            return XCTWaiter.wait(for: [expectation(for: selected, evaluatedWith: element)], timeout: 20) == .completed
        }
    }
#endif
