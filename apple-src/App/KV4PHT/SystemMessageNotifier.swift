import KV4PRadio
import UserNotifications

/// A local notification for an APRS message. The system drops it while the app is in front, as the app sets no
/// notification delegate, and the view model does not ask then either.
struct SystemMessageNotifier: APRSMessageNotifying {
    func deliver(_ notice: APRSMessageNotice) {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.text
        content.sound = .default
        let request = UNNotificationRequest(identifier: "aprs-message-\(notice.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
