import Foundation
import KV4PRadio
import UserNotifications

/// Opens the chat of a message notification that was tapped (ADR-0061). In front, the app still shows no
/// notification, as before it had a delegate. Forwarding only; the rules are in `RadioViewModel`.
///
/// The forms with a completion handler, which runs on the main thread: UIKit updates the app's snapshot in it, and stops
/// the app if that happens elsewhere, which the `async` forms did, as Swift ran them off the main thread.
@MainActor
final class NotificationOpener: NSObject, UNUserNotificationCenterDelegate {
    nonisolated static let peerKey = "peer"
    private weak var model: RadioViewModel?

    init(model: RadioViewModel) {
        self.model = model
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        nonisolated(unsafe) let completion = completionHandler
        DispatchQueue.main.async { completion([]) }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let peer = response.notification.request.content.userInfo[Self.peerKey] as? String
        nonisolated(unsafe) let completion = completionHandler
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let peer {
                    self.model?.openChat(with: peer)
                }
            }
            completion()
        }
    }
}
