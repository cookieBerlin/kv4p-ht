/// What the connection offers in its state: where PTT stands while no radio is connected, and in the settings
/// (ADR-0075).
public enum ConnectionAction: Equatable, Sendable {
    case connect, cancel, disconnect

    public init(_ status: RadioStatus) {
        switch status {
        case .disconnected, .failed: self = .connect
        case .connecting, .waitingForHello: self = .cancel
        case .ready: self = .disconnect
        }
    }

    public var title: String {
        switch self {
        case .connect: "Connect"
        case .cancel: "Cancel"
        case .disconnect: "Disconnect"
        }
    }
}

extension RadioViewModel {
    public var connectionAction: ConnectionAction { ConnectionAction(snapshot.status) }

    /// Connects, or ends the connection, also one that is being made.
    public func runConnectionAction() async {
        switch connectionAction {
        case .connect: await connect()
        case .cancel, .disconnect: await disconnect()
        }
    }
}
