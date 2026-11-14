import XCTest

/// The screenshots of the App Store, the website and the manual (docs/apple/release.md): each screen of the demo mode,
/// in light and in dark. Only `make screenshots` runs it, which sets `KV4P_SCREENSHOTS`; the images are attachments
/// named `<appearance>-<screen>`, which the script exports.
@MainActor
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        guard ProcessInfo.processInfo.environment["KV4P_SCREENSHOTS"] == "1" else {
            throw XCTSkip("Only `make screenshots` takes the screenshots")
        }
        connectToWindowServer()
        continueAfterFailure = true
    }

    func testScreenshots() throws {
        for appearance in ["light", "dark"] {
            try takeScreens(in: appearance)
        }
    }

    private func takeScreens(in appearance: String) throws {
        app = XCUIApplication()
        // A signal of S7, so that the S-meter shows one; English, whatever the language of the machine.
        app.launchArguments = [
            "-uitest-demo", "-uitest-appearance", appearance, "-uitest-signal", "7",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()
        #if os(macOS)
            // The Mac restores the windows of the last run, which may be none at all; then a new one opens.
            if !app.windows.firstMatch.waitForExistence(timeout: 10) {
                app.typeKey("n", modifierFlags: .command)
            }
        #endif
        XCTAssertTrue(app.waitForStart(), "The app did not start")
        #if os(macOS)
            app.closeAbout()
            app.resizeMainWindow(to: Self.macWindowSize)
            // The frequency field has the focus at the start, which marks its text; a click on a label takes it away.
            let label = app.staticTexts["Volume"].firstMatch
            if label.waitForExistence(timeout: 5) { label.click() }
        #endif
        // The demo connects and fills the lists after the start.
        Thread.sleep(forTimeInterval: 3)
        take("memories", appearance)
        let scan = app.buttons["Scan"].firstMatch
        if scan.waitForExistence(timeout: 2) {
            scan.tapOrClick()
            Thread.sleep(forTimeInterval: 2)
            take("scan", appearance)
            let stop = app.buttons["Stop scan"].firstMatch
            if stop.exists { stop.tapOrClick() }
        }
        app.showPage("Packets")
        take("packets", appearance)
        app.showPage("Chats")
        take("chats", appearance)
        let chat = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'N1CALL'")).firstMatch
        if chat.waitForExistence(timeout: 2) {
            chat.tapOrClick()
            Thread.sleep(forTimeInterval: 1)
            take("chat", appearance)
            let back = app.buttons["chat-back"].firstMatch
            if back.waitForExistence(timeout: 2) { back.tapOrClick() }
        }
        app.showPage("Map")
        // The tiles come from the network.
        Thread.sleep(forTimeInterval: 6)
        take("map", appearance)
        app.openSettings()
        Thread.sleep(forTimeInterval: 1)
        take("settings", appearance)
        for page in ["Simulator", "Radio", "Memories"] {
            scrollTo("settings-\(page)")
            app.openSettingsPage(page)
            Thread.sleep(forTimeInterval: 1)
            take("settings-\(page.lowercased())", appearance)
            app.goBack()
        }
        app.terminate()
    }

    /// iPhone and iPad: the list of the settings makes rows out of sight only once they come near, so it is scrolled
    /// until the link is on screen; the Mac lists its pages in a sidebar.
    private func scrollTo(_ identifier: String) {
        #if os(iOS)
            let link = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            for _ in 0..<6 where !(link.exists && link.isHittable) {
                app.swipeUp()
            }
        #endif
    }

    /// The window of the screenshots on the Mac, in points: 16:10 with a margin around it once the script puts it on the
    /// store's 2560 × 1600 pixels.
    private static let macWindowSize = CGSize(width: 1160, height: 725)

    private func take(_ screen: String, _ appearance: String) {
        #if os(macOS)
            let screenshot = app.frontWindowScreenshot()
        #else
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        #endif
        screenshot.name = "\(appearance)-\(screen)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
