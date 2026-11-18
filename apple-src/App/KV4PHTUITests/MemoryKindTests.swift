import XCTest

/// The list of memories marks the kind of each memory and shows its comment (ADR-0065).
@MainActor
final class MemoryKindTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        connectToWindowServer()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = XCUIApplication.demoArguments
        app.launch()
    }

    func testListMarksTheKindOfEachMemory() {
        // First the start, by its identifiers: a look for text anywhere on the screen reads all of it, and while the app
        // starts on a busy machine, that runs out of the time XCTest gives a query.
        XCTAssertTrue(app.waitForStart(), "The app did not start")
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
        XCTAssertTrue(row("Frequency, Calling channel").exists, "No frequency marked")
    }

    func testListHidesWhatTheRadioCannotReceive() {
        XCTAssertTrue(app.waitForStart(), "The app did not start")
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
