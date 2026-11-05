import KV4PRadio

#if os(macOS)
    import AppKit

    /// The Mac: a dialog, and the Dock icon bounces until the user comes back. The system ignores the request while
    /// the app is active.
    struct PlatformFailureAlerts: FailureAlerting {
        let usesDialog = true

        func prepare() {}

        func deliver(_ message: String) {
            _ = NSApp.requestUserAttention(.criticalRequest)
        }
    }
#else
    import UserNotifications

    /// iPhone and iPad: a local notification. The system drops it while the app is in the foreground, as the app sets
    /// no notification delegate. The app also shows the failure as a notice.
    struct PlatformFailureAlerts: FailureAlerting {
        private static let identifier = "radio-failure"

        let usesDialog = false

        func prepare() {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.identifier])
            Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
        }

        func deliver(_ message: String) {
            let content = UNMutableNotificationContent()
            content.body = message
            content.sound = .default
            let request = UNNotificationRequest(identifier: Self.identifier, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }
    }
#endif
