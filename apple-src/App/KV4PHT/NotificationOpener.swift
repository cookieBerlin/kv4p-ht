import KV4PRadio
import UserNotifications

/// Opens the chat of a message notification that was tapped (ADR-0061). In front, the app still shows no
/// notification, as before it had a delegate. Forwarding only; the rules are in `RadioViewModel`.
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
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        []
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let peer = response.notification.request.content.userInfo[Self.peerKey] as? String else { return }
        await open(peer)
    }

    private func open(_ peer: String) {
        model?.openChat(with: peer)
    }
}
