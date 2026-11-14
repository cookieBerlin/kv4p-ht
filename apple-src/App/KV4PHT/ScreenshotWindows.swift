#if os(macOS)
    import AppKit

    /// For `make screenshots` on the Mac (ADR-0076): the app's windows stand in front of everything else, also of what
    /// other apps show below the menu bar, which would otherwise be cut out of the screen with the window.
    @MainActor
    enum ScreenshotWindows {
        private static var observer: (any NSObjectProtocol)?

        /// Each window that becomes the key window, such as the settings, goes to the front level.
        static func keepInFront() {
            guard observer == nil else { return }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: nil,
                queue: .main
            ) { notification in
                let window = notification.object as? NSWindow
                MainActor.assumeIsolated { window?.level = .screenSaver }
            }
        }
    }
#endif
