import XCTest

#if os(macOS)
    import AppKit
    import ImageIO
    import UniformTypeIdentifiers
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

        /// The main window at the top left of the screen, in the given size: dragged by its title bar, beside the window
        /// buttons, and then by its bottom right corner.
        func resizeMainWindow(to size: CGSize) {
            let window = windows.firstMatch
            let origin = window.coordinate(withNormalizedOffset: .zero)
            let frame = window.frame
            let titleBar = origin.withOffset(CGVector(dx: 90, dy: 14))
            let top = menuBars.firstMatch.frame.maxY + 12
            titleBar.click(
                forDuration: 0.3,
                thenDragTo: titleBar.withOffset(CGVector(dx: 20 - frame.minX, dy: top - frame.minY))
            )
            let moved = window.frame
            let corner = window.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: moved.width - 3, dy: moved.height - 3))
            corner.click(
                forDuration: 0.3,
                thenDragTo: corner.withOffset(CGVector(dx: size.width - moved.width, dy: size.height - moved.height))
            )
        }

        /// The front window, cut out of the screen, which shows whatever else is open. The test runner cannot take a
        /// window on its own.
        func frontWindowScreenshot() -> XCTAttachment {
            let data = NSMutableData()
            let frame = windows.firstMatch.frame
            if let image = XCUIScreen.main.screenshot().image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                let scale = screenScale(of: image),
                let window = image.cropping(to: frame.applying(CGAffineTransform(scaleX: scale, y: scale)).integral),
                let png = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
            {
                CGImageDestinationAddImage(png, window, nil)
                CGImageDestinationFinalize(png)
            }
            return XCTAttachment(data: data as Data, uniformTypeIdentifier: UTType.png.identifier)
        }

        /// The pixels of the main screen for each point: its menu bar spans it, and the test runner cannot ask AppKit.
        private func screenScale(of image: CGImage) -> CGFloat? {
            let width = menuBars.firstMatch.frame.width
            return width > 0 ? CGFloat(image.width) / width : nil
        }
    }
#endif
