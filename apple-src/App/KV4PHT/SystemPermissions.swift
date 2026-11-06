import AVFoundation
import CoreBluetooth
import CoreLocation
import KV4PRadio
import UserNotifications

/// The system's permissions. Forwarding only; the rules are in `RadioViewModel`.
@MainActor
final class SystemPermissions: NSObject, PermissionChecking {
    let changes: AsyncStream<Void>
    private nonisolated let continuation: AsyncStream<Void>.Continuation
    private let location = CLLocationManager()
    /// The system answers this one only later; a change is reported through `changes`.
    private var notifications = PermissionState.notDetermined

    override init() {
        (changes, continuation) = AsyncStream.makeStream()
        super.init()
        location.delegate = self
    }

    func state(of permission: Permission) -> PermissionState {
        switch permission {
        case .bluetooth:
            switch CBManager.authorization {
            case .notDetermined: .notDetermined
            case .allowedAlways: .granted
            default: .denied
            }
        case .microphone:
            switch AVAudioApplication.shared.recordPermission {
            case .undetermined: .notDetermined
            case .granted: .granted
            default: .denied
            }
        case .location:
            switch location.authorizationStatus {
            case .notDetermined: .notDetermined
            case .denied, .restricted: .denied
            default: .granted
            }
        case .notifications:
            refreshedNotifications()
        }
    }

    /// What is known now; a newer answer of the system follows through `changes`.
    private func refreshedNotifications() -> PermissionState {
        refreshNotifications()
        return notifications
    }

    private func refreshNotifications() {
        Task {
            let state: PermissionState =
                switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
                case .notDetermined: .notDetermined
                case .denied: .denied
                default: .granted
                }
            if state != notifications {
                notifications = state
                continuation.yield()
            }
        }
    }

    func request(_ permission: Permission) {
        switch permission {
        case .bluetooth:
            break  // the connection asks, by creating its central
        case .microphone:
            Task {
                _ = await AVAudioApplication.requestRecordPermission()
                continuation.yield()
            }
        case .location:
            location.requestWhenInUseAuthorization()
        case .notifications:
            Task {
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                refreshNotifications()
            }
        }
    }
}

extension SystemPermissions: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        continuation.yield()
    }
}
