/// A message to this station, for a notification (ADR-0058).
public struct APRSMessageNotice: Equatable, Sendable {
    /// One for each message, so that notifications do not replace each other.
    public let id: Int64
    /// The sender.
    public let title: String
    public let text: String
    /// The chat a tap on the notification opens (ADR-0061).
    public let peer: String
}

/// The system's notifications; implemented in the app target.
@MainActor
public protocol APRSMessageNotifying {
    func deliver(_ notice: APRSMessageNotice)
}
