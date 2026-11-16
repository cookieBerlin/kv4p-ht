import XCTest

/// The first start of the app on a machine, before the tests of a run (ADR-0072). On a freshly booted simulator the
/// first launch fails at times; `scripts/a11y.sh` runs this test first and once more if it fails, so that a failed launch
/// costs seconds rather than a test of minutes. No selection of the script includes it otherwise.
@MainActor
final class WarmUpTests: XCTestCase {
    func testTheAppStarts() {
        connectToWindowServer()
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-demo"]
        app.launch()
        XCTAssertTrue(app.waitForStart(), "The app did not start")
        app.terminate()
    }
}
