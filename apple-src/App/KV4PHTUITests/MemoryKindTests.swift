import XCTest

/// The list of memories marks repeaters and beacons and shows their comment (ADR-0065).
@MainActor
final class MemoryKindTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest-demo"]
        app.launch()
    }

    func testListMarksRepeatersAndBeacons() {
        #if os(macOS)
            app.closeAbout()
        #endif
        // A row is one element; the Mac gives its text as the value, iOS as the label.
        let row = { (text: String) in
            self.app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)
            )
            .firstMatch
        }
        XCTAssertTrue(row("Repeater, Local repeater").waitForExistence(timeout: 60), "No repeater marked")
        XCTAssertTrue(row("Example repeater").exists, "No comment shown")
        XCTAssertTrue(row("Beacon, Local beacon").exists, "No beacon marked")
    }

    func testListHidesWhatTheRadioCannotReceive() {
        #if os(macOS)
            app.closeAbout()
        #endif
        let hint = app.staticTexts["1 memory for 70 cm is hidden: this radio receives 2 m."].firstMatch
        XCTAssertTrue(hint.waitForExistence(timeout: 60), "No hint for the hidden memory")
        let hidden = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'Far repeater' OR value CONTAINS 'Far repeater'")
        )
        XCTAssertEqual(hidden.count, 0, "A memory for 70 cm is listed")
    }
}
