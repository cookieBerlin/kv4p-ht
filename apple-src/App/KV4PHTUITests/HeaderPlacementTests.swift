import XCTest

/// The header with the frequency stands with the memories only: on a phone on their page, in a wide window in their
/// column, beside which the packets, the chats and the map reach to the top (ADR-0074).
@MainActor
final class HeaderPlacementTests: XCTestCase {
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

    private var frequency: XCUIElement {
        app.descendants(matching: .any)["frequency"].firstMatch
    }

    func testThePhoneShowsTheHeaderOnTheMemoriesOnly() throws {
        let packets = app.buttons["page-Packets"].firstMatch
        guard packets.waitForExistence(timeout: 60) else {
            throw XCTSkip("Only a phone has the page bar")
        }
        app.buttons["page-Memories"].firstMatch.tap()
        XCTAssertTrue(frequency.waitForExistence(timeout: 5), "No header on the memories")
        packets.tap()
        XCTAssertTrue(frequency.waitForNonExistence(timeout: 5), "The header stays on the packets")
        app.buttons["page-Map"].firstMatch.tap()
        XCTAssertFalse(frequency.exists, "The header is on the map")
        app.buttons["page-Memories"].firstMatch.tap()
        XCTAssertTrue(frequency.waitForExistence(timeout: 5), "The header does not come back")
    }

    func testAWideWindowShowsThePacketsBesideTheHeader() throws {
        guard !app.buttons["page-Packets"].firstMatch.waitForExistence(timeout: 10) else {
            throw XCTSkip("A phone has pages instead")
        }
        #if os(macOS)
            let packets = app.radioButtons.matching(NSPredicate(format: "label BEGINSWITH 'Packets'")).firstMatch
        #else
            let packets = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Packets'")).firstMatch
        #endif
        XCTAssertTrue(frequency.waitForExistence(timeout: 30), "No header")
        XCTAssertTrue(packets.waitForExistence(timeout: 5), "No packets beside the memories")
        XCTAssertLessThan(packets.frame.minY, frequency.frame.minY, "The packets do not reach above the frequency")
        XCTAssertGreaterThan(packets.frame.minX, frequency.frame.maxX, "The packets are not beside the header")
    }
}
