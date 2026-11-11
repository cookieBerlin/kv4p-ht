import XCTest

#if os(macOS)
    import AppKit
#endif

extension XCTestCase {
    /// Since Xcode 27.2 the Mac's test runner has no connection to the window server of its own, and stops at its first
    /// click or key, when XCTest asks for the display; AppKit's application makes the connection. Before, a test that
    /// used AppKit, as the audit does, made it by the way for the tests after it. Nothing to do elsewhere.
    @MainActor func connectToWindowServer() {
        #if os(macOS)
            _ = NSApplication.shared
        #endif
    }
}

#if os(macOS)
    extension XCUIApplication {
        /// The Mac opens the windows of the last run again, such as the About window, which would stand in front.
        func closeAbout() {
            let close = windows["About kv4p HT"].buttons[XCUIIdentifierCloseWindow]
            if close.exists { close.click() }
        }
    }
#endif
