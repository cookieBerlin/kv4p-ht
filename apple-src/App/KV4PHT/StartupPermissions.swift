import AVFoundation
import CoreLocation

/// Asks for the permissions when the app starts, as the Android app does (ADR-0040). Bluetooth comes with the scan,
/// which starts at the same time. The system does not ask again for what the user has already answered.
@MainActor
enum StartupPermissions {
    /// The system drops the location request if its manager goes away.
    private static let location = CLLocationManager()

    static func request() async {
        _ = await AVAudioApplication.requestRecordPermission()
        location.requestWhenInUseAuthorization()
        PlatformFailureAlerts().prepare()
    }
}
