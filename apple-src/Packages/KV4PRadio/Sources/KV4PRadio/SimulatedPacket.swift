import Foundation
import KV4PAPRS

/// An APRS packet the simulator can receive, with placeholder data only.
public enum SimulatedPacket: CaseIterable, Sendable {
    case message, position, object, weather, status

    public var label: String {
        switch self {
        case .message: "Message"
        case .position: "Position"
        case .object: "Object"
        case .weather: "Weather"
        case .status: "Status"
        }
    }

    /// The packet in TNC2 form; a message goes to `callsign`, or to a placeholder without one.
    func tnc2(to callsign: String) -> String {
        switch self {
        case .message:
            let recipient = callsign.isEmpty ? "N0CALL" : callsign
            let field = recipient.padding(toLength: 9, withPad: " ", startingAt: 0)
            return "N1CALL>APRS::\(field):Test message"
        case .position: return "N1CALL>APRS:=4903.50N/07201.75W-Test position"
        case .object: return "N1CALL>APRS:;TESTOBJ  *111111z4903.50N/07201.75W-Test object"
        case .weather: return "N1CALL>APRS:=4903.50N/07201.75W_220/004g005t077r000p000P000h50b09900"
        case .status: return "N1CALL>APRS:>Test status"
        }
    }
}

/// How the station the simulator plays answers a message (ADR-0061).
public enum SimulatedMessageAnswer: String, CaseIterable, Codable, Sendable {
    case acknowledge, acknowledgeAndReply, reject, none

    public var label: String {
        switch self {
        case .acknowledge: "Acknowledge"
        case .acknowledgeAndReply: "Acknowledge and reply"
        case .reject: "Reject"
        case .none: "No answer"
        }
    }
}

/// The other station of a message sent over the simulator, so that chats can be tried without a radio.
enum SimulatedStation {
    struct Answer: Equatable {
        let delay: Duration
        let tnc2: String
    }

    static let acknowledgementDelay = Duration.seconds(2)

    /// `isFirst`: not a repeat, which gets an acknowledgement again but no second reply.
    static func answers(
        to packet: APRSPacket,
        with answer: SimulatedMessageAnswer,
        replyDelay: Duration,
        isFirst: Bool
    ) -> [Answer] {
        guard let message = packet.info.message, !message.isAck, !message.isRej, let number = message.number,
            !number.isEmpty, APRSController.requiresAcknowledgement(message.target)
        else { return [] }
        let header = "\(message.target)>APRS::\(packet.source.padding(toLength: 9, withPad: " ", startingAt: 0)):"
        let acknowledgement = Answer(delay: acknowledgementDelay, tnc2: header + "ack" + number)
        switch answer {
        case .acknowledge:
            return [acknowledgement]
        case .acknowledgeAndReply:
            let reply = Answer(delay: replyDelay, tnc2: header + "Test reply to your message \(number){\(number)")
            return isFirst ? [acknowledgement, reply] : [acknowledgement]
        case .reject:
            return [Answer(delay: acknowledgementDelay, tnc2: header + "rej" + number)]
        case .none:
            return []
        }
    }
}
