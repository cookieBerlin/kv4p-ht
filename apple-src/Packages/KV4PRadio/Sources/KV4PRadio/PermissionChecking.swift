/// A system permission the app needs for part of its functions (ADR-0040).
public enum Permission: CaseIterable, Sendable {
    case bluetooth, microphone, location

    /// What the app cannot do without the permission.
    public var deniedMessage: String {
        switch self {
        case .bluetooth: "Bluetooth access is not allowed, so the app cannot reach a radio over Bluetooth."
        case .microphone: "Microphone access is not allowed, so the app cannot transmit."
        case .location: "Location access is not allowed, so the app cannot send position beacons."
        }
    }
}

public enum PermissionState: Sendable {
    case notDetermined, granted, denied
}

/// The system's permissions; implemented in the app target.
@MainActor
public protocol PermissionChecking {
    /// Fires when the system reports a change; Bluetooth reports none outside a central.
    var changes: AsyncStream<Void> { get }
    func state(of permission: Permission) -> PermissionState
    /// Asks the user if that has not happened yet. Does not wait for the answer.
    func request(_ permission: Permission)
}
