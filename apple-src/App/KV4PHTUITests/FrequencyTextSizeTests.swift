import XCTest

/// The line of the frequency is an instrument: with the largest text, it still fits its column, from the first digit
/// to the squelch symbol.
@MainActor
final class FrequencyTextSizeTests: XCTestCase {
    func testTheFrequencyFitsWithTheLargestText() throws {
        #if os(macOS)
            throw XCTSkip("The Mac has no larger text for apps")
        #else
            let app = XCUIApplication()
            app.launchArguments = [
                "-uitest-demo", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            ]
            app.launch()
            let field = app.textFields["frequency"].firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 60), "No frequency field")
            let pushToTalk = app.buttons.matching(NSPredicate(format: "label == 'Push to talk'")).firstMatch
            XCTAssertTrue(pushToTalk.waitForExistence(timeout: 60), "No PTT while connected")
            let squelch = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Squelch'")).firstMatch
            XCTAssertTrue(squelch.exists, "No squelch symbol")
            // PTT spans the column within the same margins as the line of the frequency.
            let column = pushToTalk.frame.insetBy(dx: -1, dy: 0)
            XCTAssertGreaterThanOrEqual(field.frame.minX, column.minX, "The frequency is cut off on the left")
            XCTAssertLessThanOrEqual(squelch.frame.maxX, column.maxX, "The squelch symbol is cut off on the right")
        #endif
    }
}
