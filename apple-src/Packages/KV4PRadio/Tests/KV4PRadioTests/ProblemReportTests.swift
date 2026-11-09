import Foundation
import Testing

@testable import KV4PRadio

/// What a report holds, and what must not be in it (ADR-0059).
@Suite("Problem report")
struct ProblemReportTests {
    private static let environment = ProblemReport.Environment(
        version: "1.2 (3)",
        device: "iPhone99,1",
        system: "iOS 26.0"
    )

    @Test("it has the versions, the device, the log and the crashes")
    func content() {
        let text = ProblemReport.text(
            environment: Self.environment,
            firmware: "15, SA818 VHF",
            log: "A line\n",
            crashes: ["{\"crash\":1}"],
            callsign: ""
        )
        #expect(text.contains("App: 1.2 (3)"))
        #expect(text.contains("Device: iPhone99,1"))
        #expect(text.contains("System: iOS 26.0"))
        #expect(text.contains("Firmware: 15, SA818 VHF"))
        #expect(text.contains("A line"))
        #expect(text.contains("{\"crash\":1}"))
    }

    @Test("without crashes it says so")
    func noCrashes() {
        let text = ProblemReport.text(
            environment: Self.environment,
            firmware: "Unknown",
            log: "",
            crashes: [],
            callsign: ""
        )
        #expect(text.contains("Crashes: none reported"))
    }

    @Test("the callsign becomes a placeholder, in any case and with any SSID, and nothing else changes")
    func redacts() {
        let text = "From n0call and N0CALL-7 to AN0CALL and N0CALLX"
        #expect(
            ProblemReport.redacted(text, callsign: "N0CALL-9")
                == "From [callsign] and [callsign]-7 to AN0CALL and N0CALLX"
        )
        #expect(ProblemReport.redacted(text, callsign: " ") == text)
    }

    @Test("the whole text is redacted, also the crashes")
    func redactsAll() {
        let text = ProblemReport.text(
            environment: Self.environment,
            firmware: "Unknown",
            log: "N0CALL\n",
            crashes: ["n0call"],
            callsign: "N0CALL"
        )
        #expect(!text.uppercased().contains("N0CALL"))
    }

    @Test("an issue is prepared on the project's page, without the log")
    func issue() throws {
        let url = try #require(ProblemReport.issueURL(environment: Self.environment, firmware: "15"))
        #expect(url.absoluteString.hasPrefix(AboutInfo.sourceAddress + "/issues/new?"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let body = items.first { $0.name == "body" }?.value ?? ""
        #expect(body.contains("1.2 (3)"))
        #expect(body.contains("iPhone99,1"))
        #expect(body.contains("iOS 26.0"))
        #expect(body.contains("Firmware: 15"))
        #expect(items.contains { $0.name == "title" })
    }
}

/// Crash data that waits to be reported (ADR-0059).
@Suite("Crash reports")
struct CrashReportStoreTests {
    private static func folder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    }

    @Test("a crash stays across restarts, and is new until it has been seen")
    func keeps() {
        let folder = Self.folder()
        let store = CrashReportStore(folder: folder)
        #expect(!store.hasNew)
        #expect(store.add(id: "1", json: "first"))
        #expect(store.hasNew)
        let again = CrashReportStore(folder: folder)
        #expect(again.hasNew)
        again.markSeen()
        #expect(!again.hasNew)
        #expect(CrashReportStore(folder: folder).all() == ["first"])
    }

    @Test("the same crash does not come twice, also after it has been seen")
    func once() {
        let store = CrashReportStore(folder: Self.folder())
        #expect(store.add(id: "1", json: "first"))
        store.markSeen()
        #expect(!store.add(id: "1", json: "first"))
        #expect(!store.hasNew)
        #expect(store.all() == ["first"])
    }

    @Test("the newest 5 stay, and all can go")
    func limit() {
        let store = CrashReportStore(folder: Self.folder())
        for number in 1...7 {
            #expect(store.add(id: "\(number)", json: "\(number)"))
        }
        #expect(store.all() == ["3", "4", "5", "6", "7"])
        store.deleteAll()
        #expect(store.all().isEmpty)
        #expect(!store.hasNew)
    }
}
