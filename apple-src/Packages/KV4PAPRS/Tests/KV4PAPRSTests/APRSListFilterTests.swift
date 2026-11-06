import Foundation
import Testing

@testable import KV4PAPRS

/// What the APRS list looks for (ADR-0057).
@Suite("APRS list filter")
struct APRSListFilterTests {
    private static func event(_ line: String) -> APRSEvent {
        var controller = APRSController(startMs: 0)
        controller.callsign = "N9CALL"
        _ = controller.receive(internetLine: line, atMs: 1)
        return controller.events[0]
    }

    private static let toMe = event("N1CALL>APRS::N0CALL   :Hello")
    private static let toMySSID = event("N1CALL>APRS::N0CALL-7 :Hello")
    private static let fromMe = event("N0CALL-9>APRS::N1CALL   :Hello")
    private static let toOther = event("N1CALL>APRS::N2CALL   :Hello")
    private static let bulletin = event("N1CALL>APRS::BLN1     :Hello")
    private static let everyone = event("N1CALL>APRS::QST      :Hello")
    private static let similar = event("N1CALL>APRS::N0CALLX  :Hello")
    private static let position = event("N0CALL>APRS:=4903.50N/07201.75W>Hello")

    @Test("an empty filter finds everything")
    func empty() {
        let filter = APRSListFilter()
        #expect(filter.isEmpty)
        #expect(filter.matches(Self.toOther, ownCallsign: "N0CALL"))
        #expect(filter.matches(Self.position, ownCallsign: "N0CALL"))
    }

    @Test("for me are only messages from or to this station, with any SSID")
    func forMe() {
        let filter = APRSListFilter(isForMe: true)
        #expect(!filter.isEmpty)
        for event in [Self.toMe, Self.toMySSID, Self.fromMe] {
            #expect(filter.matches(event, ownCallsign: "N0CALL"))
            #expect(filter.matches(event, ownCallsign: "n0call-7 "))
        }
        for event in [Self.toOther, Self.bulletin, Self.everyone, Self.similar, Self.position] {
            #expect(!filter.matches(event, ownCallsign: "N0CALL"))
        }
    }

    @Test("without a callsign nothing is for me")
    func forMeWithoutCallsign() {
        #expect(!APRSListFilter(isForMe: true).matches(Self.toMe, ownCallsign: ""))
        #expect(!Self.toMe.isMessage(of: " "))
    }

    @Test("the callsign is found in the sender or recipient, in any case")
    func callsign() {
        let filter = APRSListFilter(callsign: " n2 ")
        #expect(!filter.isEmpty)
        #expect(filter.matches(Self.toOther, ownCallsign: "N0CALL"))
        #expect(!filter.matches(Self.toMe, ownCallsign: "N0CALL"))
        #expect(APRSListFilter(callsign: "n1").matches(Self.toOther, ownCallsign: ""))
    }

    @Test("the types narrow it, and all parts must fit")
    func kinds() {
        let filter = APRSListFilter(kinds: [.position, .weather])
        #expect(!filter.isEmpty)
        #expect(filter.matches(Self.position, ownCallsign: ""))
        #expect(!filter.matches(Self.toMe, ownCallsign: ""))
        #expect(!APRSListFilter(callsign: "N1", kinds: [.position]).matches(Self.position, ownCallsign: ""))
        #expect(!APRSListFilter(kinds: [.position], isForMe: true).matches(Self.toMe, ownCallsign: "N0CALL"))
    }

    @Test("a filter can be remembered")
    func codable() throws {
        let filter = APRSListFilter(callsign: "N1", kinds: [.message, .status], isForMe: true)
        let data = try JSONEncoder().encode(filter)
        #expect(try JSONDecoder().decode(APRSListFilter.self, from: data) == filter)
    }

    @Test("each type a filter offers has a name")
    func names() {
        #expect(APRSEvent.Kind.filterOptions.count == 7)
        #expect(Set(APRSEvent.Kind.filterOptions.map(\.filterName)).count == 7)
    }
}
