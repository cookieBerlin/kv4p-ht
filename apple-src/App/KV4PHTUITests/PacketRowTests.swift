import XCTest

// iPhone and iPad only: a finger needs the room a pointer does not.
#if os(iOS)
    /// The rows of the packets, as a finger reaches them.
    @MainActor
    final class PacketRowTests: XCTestCase {
        private var app: XCUIApplication!

        override func setUp() async throws {
            continueAfterFailure = false
            app = XCUIApplication()
            app.launchArguments = ["-uitest-demo"]
            app.launch()
            XCTAssertTrue(app.waitForStart(), "The app did not start")
            app.showPage("Packets")
        }

        /// The coordinates are small text, but the link to the map they are takes a finger: 44 points high, as Apple asks.
        func testTheLinkToTheMapIsTallEnoughForAFinger() {
            let isMapLink = NSPredicate(format: "label BEGINSWITH 'Open ' AND label ENDSWITH ' in Maps'")
            let link = app.descendants(matching: .any).matching(isMapLink).firstMatch
            XCTAssertTrue(link.waitForExistence(timeout: 60), "No packet with a position")
            XCTAssertGreaterThanOrEqual(link.frame.height, 44, "The link to the map is too small for a finger")
        }
    }
#endif
