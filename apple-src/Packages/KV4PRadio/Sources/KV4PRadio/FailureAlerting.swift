/// How the platform tells the user of a failed connection when the app may not be in front (ADR-0039).
@MainActor
public protocol FailureAlerting {
    /// The dialog opens in the background too and waits for the user; otherwise it opens only in the foreground.
    var showsDialogInBackground: Bool { get }
    /// Called before each connection, while the user is in the app. Must not wait for the user.
    func prepare()
    /// Called once per failure. Has no visible effect while the app is in the foreground.
    func deliver(_ message: String)
}
