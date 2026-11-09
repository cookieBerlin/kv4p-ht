import KV4PRadio
import UserNotifications

/// A local notification for an APRS message, which opens its chat when tapped. In front, the delegate shows none, and
/// the view model does not ask then either.
struct SystemMessageNotifier: APRSMessageNotifying {
    let diagnostics: DiagnosticLog

    func deliver(_ notice: APRSMessageNotice) {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.text
        content.sound = .default
        content.userInfo = [NotificationOpener.peerKey: notice.peer]
        let request = UNNotificationRequest(identifier: "aprs-message-\(notice.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { [diagnostics] error in
            if let error {
                diagnostics.log(.error, .app, "Message notification: \(DiagnosticLog.describe(error))")
            }
        }
    }
}
