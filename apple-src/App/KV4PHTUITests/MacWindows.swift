import XCTest

#if os(macOS)
    extension XCUIApplication {
        /// The Mac opens the windows of the last run again, such as the About window, which would stand in front.
        func closeAbout() {
            let close = windows["About kv4p HT"].buttons[XCUIIdentifierCloseWindow]
            if close.exists { close.click() }
        }
    }
#endif
