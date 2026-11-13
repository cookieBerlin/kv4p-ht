import CoreData
import Foundation
import KV4PDiagnostics

/// The events of CloudKit's sync: forwards when one has finished (ADR-0052), and logs when one has failed (ADR-0059).
public enum CloudKitSyncEvents {
    /// When an upload or download to iCloud has finished without a problem.
    /// Runs for as long as the app does.
    public static func logFailures(to diagnostics: DiagnosticLog) -> Task<Void, Never> {
        Task {
            let events = NotificationCenter.default.notifications(
                named: NSPersistentCloudKitContainer.eventChangedNotification
            )
            for await notification in events {
                let key = NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                if let event = notification.userInfo?[key] as? NSPersistentCloudKitContainer.Event,
                    event.endDate != nil, !event.succeeded
                {
                    let reason = event.error.map(DiagnosticLog.describe) ?? "no reason given"
                    let kind = direction(of: event.type)?.rawValue ?? "setup"
                    diagnostics.log(.error, .sync, "Memory sync failed, \(kind): \(reason)")
                }
            }
        }
    }

    static var finishedSyncs: AsyncStream<MemorySync> {
        AsyncStream { continuation in
            let task = Task {
                let events = NotificationCenter.default.notifications(
                    named: NSPersistentCloudKitContainer.eventChangedNotification
                )
                for await notification in events {
                    let key = NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                    if let event = notification.userInfo?[key] as? NSPersistentCloudKitContainer.Event,
                        event.succeeded, let end = event.endDate, let direction = direction(of: event.type)
                    {
                        continuation.yield(MemorySync(direction: direction, started: event.startDate, finished: end))
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// An import brings the changes of other devices, an export takes this one's up; the setup moves no memories.
    private static func direction(of type: NSPersistentCloudKitContainer.EventType) -> MemorySync.Direction? {
        switch type {
        case .import: .download
        case .export: .upload
        default: nil
        }
    }
}
