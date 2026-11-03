import AVFoundation
import CoreBluetooth
import CoreLocation
import KV4PRadio

/// The system's permissions. Forwarding only; the rules are in `RadioViewModel`.
@MainActor
final class SystemPermissions: NSObject, PermissionChecking {
    let changes: AsyncStream<Void>
    private nonisolated let continuation: AsyncStream<Void>.Continuation
    private let location = CLLocationManager()

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
        }
    }
}

extension SystemPermissions: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        continuation.yield()
    }
}
