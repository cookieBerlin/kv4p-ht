import XCTest

/// Finding a memory by its name asks the accessibility of each element for its title, as XCTest and assistive
/// technologies do. On the Mac, SwiftUI once resolved the role and the label of a memory row in a loop, until the app
/// overflowed its stack and stopped.
@MainActor
final class MemoryRowAccessibilityTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        connectToWindowServer()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest-demo"]
        app.launch()
        XCTAssertTrue(app.waitForStart(), "The app did not start")
        #if os(macOS)
            app.closeAbout()
        #endif
    }

    func testMemoriesAreFoundByName() {
        // The demo fills the memories after the start.
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Calling channel'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "No memory in the list")
        // By name, which asks each element for its title.
        _ = app.staticTexts["Calling channel"].exists
        XCTAssertTrue(app.state == .runningForeground, "The app stopped while a memory was looked up by name")
    }

    func testManagedMemoriesAreFoundByName() {
        app.openSettings()
        app.openSettingsPage("Memories")
        let group = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'No group'")).firstMatch
        XCTAssertTrue(group.waitForExistence(timeout: 10), "No group in the memory settings")
        group.tapOrClick()
        _ = app.staticTexts["Calling channel"].exists
        XCTAssertTrue(app.state == .runningForeground, "The app stopped while a memory was looked up by name")
    }
}
