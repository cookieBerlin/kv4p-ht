import Foundation
import KV4PTestSupport
import Testing

@testable import KV4PAPRS

/// Android `AprsObjectSummary`: a repeater object reads as frequencies and range.
@Suite("APRS object summary vectors")
struct APRSObjectSummaryVectorTests {
    struct Input: Decodable, Sendable {
        let name: String?
        let comment: String?
    }

    struct Expected: Decodable, Sendable {
        let card: String
        let label: String
    }

    static let vectors = (try? VectorFile<Input, Expected>.load("aprs-object-summary", from: .module)) ?? []

    @Test("vector file is present")
    func vectorsPresent() {
        #expect(Self.vectors.count == 23)
    }

    @Test("the summary is that of the Android app", arguments: vectors)
    func summary(vector: VectorFile<Input, Expected>.Vector) {
        let summary = APRSObjectSummary(name: vector.input.name, comment: vector.input.comment)
        #expect(summary.cardText == vector.expected.card)
        #expect(summary.mapLabel == vector.expected.label)
    }
}

/// How each type of packet reads in the list, in the chosen units (ADR-0055).
@Suite("APRS packet text")
struct APRSPacketTextTests {
    private static let us = Locale(identifier: "en_US")
    private static let germany = Locale(identifier: "de_DE")
    private static let britain = Locale(identifier: "en_GB")

    private static func event(_ line: String) -> APRSEvent? {
        var controller = APRSController(startMs: 0)
        controller.callsign = "N0CALL"
        _ = controller.receive(internetLine: line, atMs: 1)
        return controller.events.first
    }

    private static let weather = "N1CALL>APRS:=4903.50N/07201.75W_220/004g005t077r000p010P000h50b09900s002"

    @Test("metric and imperial say what they mean")
    func units() {
        #expect(APRSUnits.metric.temperature(77, locale: Self.us) == "25 °C")
        #expect(APRSUnits.imperial.temperature(77, locale: Self.us) == "77 °F")
        #expect(APRSUnits.metric.speed(mph: 10, locale: Self.us) == "16 km/h")
        #expect(APRSUnits.imperial.speed(mph: 10, locale: Self.us) == "10 mph")
        #expect(APRSUnits.metric.rain(inches: 1, locale: Self.us) == "25.4 mm")
        #expect(APRSUnits.imperial.rain(inches: 1, locale: Self.us) == "1 in")
        #expect(APRSUnits.metric.snow(inches: 1, locale: Self.us) == "2.5 cm")
        #expect(APRSUnits.imperial.snow(inches: 1, locale: Self.us) == "1 in")
        #expect(APRSUnits.metric.distance(meters: 12_300, locale: Self.us) == "12.3 km")
        #expect(APRSUnits.imperial.distance(meters: 16_093.44, locale: Self.us) == "10 mi")
    }

    @Test("the system decides by the region, also where it mixes")
    func system() {
        #expect(APRSUnits.system.temperature(77, locale: Self.germany) == "25 °C")
        #expect(APRSUnits.system.temperature(77, locale: Self.us) == "77 °F")
        #expect(APRSUnits.system.temperature(77, locale: Self.britain) == "25 °C")
        #expect(APRSUnits.system.speed(mph: 10, locale: Self.britain) == "10 mph")
        #expect(APRSUnits.system.distance(meters: 16_093.44, locale: Self.britain) == "10 mi")
        #expect(APRSUnits.system.rain(inches: 1, locale: Self.britain) == "25.4 mm")
        #expect(APRSUnits.system.rain(inches: 1, locale: Self.germany) == "25,4 mm")
    }

    @Test("the choices have labels", arguments: APRSUnits.allCases)
    func labels(units: APRSUnits) {
        #expect(!units.label.isEmpty)
    }

    @Test("weather reads as lines of what was reported")
    func weather() throws {
        let event = try #require(Self.event(Self.weather))
        #expect(
            event.text(units: .metric, locale: Self.us)
                == "25 °C · 50 % · 990 hPa\nWind SW 6 km/h · Rain 2.5 mm · Snow 5.1 cm"
        )
        #expect(
            event.text(units: .imperial, locale: Self.us)
                == "77 °F · 50 % · 990 hPa\nWind SW 4 mph · Rain 0.1 in · Snow 2 in"
        )
    }

    @Test("what a station does not report is left out, as a 0 would say something else")
    func missing() throws {
        let empty = try #require(Self.event("N1CALL>APRS:=4903.50N/07201.75W_.../...t...h.."))
        #expect(empty.text(units: .metric, locale: Self.us) == nil)
        let partly = try #require(Self.event("N1CALL>APRS:=4903.50N/07201.75W_.../...t032r000p000P000"))
        #expect(partly.text(units: .metric, locale: Self.us) == "0 °C")
        let calm = try #require(Self.event("N1CALL>APRS:=4903.50N/07201.75W_000/000t050h00"))
        #expect(calm.text(units: .metric, locale: Self.us) == "10 °C · 100 %\nWind N 0 km/h")
    }

    @Test("a repeater object reads as its summary, a removed one says so")
    func objects() throws {
        let live = try #require(Self.event("N1CALL>APRS:;145.500-R*111111z4903.50N/07201.75Wr145.500MHz -0.600 MHz"))
        #expect(live.text(units: .metric, locale: Self.us) == "145.5 MHz · Offset -0.6 MHz")
        #expect(!live.isRemovedObject)
        #expect(live.mapLabel == "145.500-R · 145.5 MHz")
        let removed = try #require(Self.event("N1CALL>APRS:;TESTOBJ  _111111z4903.50N/07201.75W-Gone"))
        #expect(removed.isRemovedObject)
        #expect(removed.mapLabel == "TESTOBJ")
    }

    @Test("a position shows its comment without the marks of a radio")
    func position() throws {
        let event = try #require(Self.event("N0CALL-7>S32U6T:`(_fn\"Oj/`Hello_3"))
        #expect(event.text(units: .metric, locale: Self.us) == "Hello")
        #expect(event.mapLabel == "N0CALL-7")
    }

    @Test(
        "each type has a name and its text",
        arguments: [
            ("N1CALL>APRS::N0CALL   :Hello", "Message", "Hello", false),
            ("N1CALL>APRS::QST      :Hello", "Bulletin", "Hello", false),
            ("N1CALL>APRS::BLN1     :Hello", "Bulletin", "Hello", false),
            ("N1CALL>APRS:>Test status", "Status", "Test status", false),
            ("N1CALL>APRS:<IGATE,MSG_CNT=3,LOC_CNT=7", "Capabilities", "IGate · 3 messages · 7 local stations", false),
            ("N1CALL>APRS:T#005,199,000,255,073,123,01101001", "Telemetry", "T#005,199,000,255,073,123,01101001", true),
            ("N1CALL>APRS:?APRS?", "Query", "?APRS?", true),
            ("N1CALL>APRS:{unknown", "Unknown packet", "{unknown", true),
            ("N1CALL>APRS:=4903.50N/07201.75W>Hello", "Position", "Hello", false),
            ("N1CALL>APRS:;TESTOBJ  *111111z4903.50N/07201.75W-Fair", "Object", "Fair", false),
        ] as [(String, String, String, Bool)]
    )
    func types(line: String, type: String, text: String, isRaw: Bool) throws {
        let event = try #require(Self.event(line))
        #expect(event.typeName == type)
        #expect(event.text(units: .metric, locale: Self.us) == text)
        #expect(event.isRawText == isRaw)
    }

    @Test("a weather report has its name")
    func weatherName() throws {
        #expect(try #require(Self.event(Self.weather)).typeName == "Weather")
    }

    @Test("the details start with the type of packet, also without a symbol")
    func details() throws {
        let message = try #require(Self.event("N1CALL>APRS::N0CALL   :Hello"))
        #expect(message.details == ["Message"])
        let position = try #require(Self.event("N1CALL>APRS:=4903.50N/07201.75W>Hello"))
        #expect(position.details == ["Position", "Car", "Code: />"])
    }

    @Test("the line below a packet names what is not plain from the rest")
    func captions() throws {
        let status = try #require(Self.event("N1CALL>APRS:>Test status"))
        #expect(status.caption == "Status · Internet")
        let position = try #require(Self.event("N1CALL>APRS:=4903.50N/07201.75W>Hello"))
        #expect(position.caption == "Car · Internet")
        let removed = try #require(Self.event("N1CALL>APRS:;TESTOBJ  _111111z4903.50N/07201.75W-Gone"))
        #expect(removed.caption == "House · Internet · Removed")
        var message = try #require(Self.event("N1CALL>APRS::N0CALL   :Hello"))
        message.isInternetOnly = false
        #expect(message.caption == nil)
        let bulletin = try #require(Self.event("N1CALL>APRS::QST      :Hello"))
        #expect(bulletin.caption == "Bulletin · Internet")
    }

    @Test("internet and digipeated are marks of their own")
    func marks() throws {
        let event = try #require(Self.event("N1CALL>APRS:>Test status"))
        #expect(event.isInternetOnly)
        #expect(event.marks == ["Internet"])
        var digipeated = event
        digipeated.isInternetOnly = false
        digipeated.isDigipeated = true
        #expect(digipeated.marks == ["Digipeated"])
    }
}
