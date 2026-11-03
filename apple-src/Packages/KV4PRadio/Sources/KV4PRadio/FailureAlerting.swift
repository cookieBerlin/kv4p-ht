/// How the platform tells the user of a failed connection (ADR-0039).
@MainActor
public protocol FailureAlerting {
    /// The failure opens a dialog; otherwise it shows as a notice.
    var usesDialog: Bool { get }
    /// Called before each connection, while the user is in the app. Must not wait for the user.
    func prepare()
    /// Called once per failure. Has no visible effect while the app is in the foreground.
    func deliver(_ message: String)
}
