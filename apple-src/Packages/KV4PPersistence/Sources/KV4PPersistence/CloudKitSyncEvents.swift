import CoreData
import Foundation

/// The events of CloudKit's sync: forwards when one has finished (ADR-0052).
enum CloudKitSyncEvents {
    /// When an upload or download to iCloud has finished without a problem.
    static var finishedSyncs: AsyncStream<Date> {
        AsyncStream { continuation in
            let task = Task {
                let events = NotificationCenter.default.notifications(
                    named: NSPersistentCloudKitContainer.eventChangedNotification
                )
                for await notification in events {
                    let key = NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                    if let event = notification.userInfo?[key] as? NSPersistentCloudKitContainer.Event,
                        event.type != .setup, event.succeeded, let end = event.endDate
                    {
                        continuation.yield(end)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
