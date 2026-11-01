import KV4PProtocol
import Testing

@testable import KV4PRadio

/// The About window: version, build and the licences of what the app contains.
@Suite("About")
struct AboutInfoTests {
    @Test("version and build come from the bundle, with the firmware the app ships")
    func version() {
        let about = AboutInfo(info: ["CFBundleShortVersionString": "0.1", "CFBundleVersion": "7"])
        #expect(about.version == "Version 0.1 (7)")
        #expect(about.firmware == "Firmware \(KV4P.packagedFirmwareVersion) for USB updates")
        #expect(AboutInfo(info: [:]).version == "Version unknown")
        #expect(AboutInfo(info: ["CFBundleShortVersionString": "0.1"]).version == "Version 0.1")
    }

    @Test("a release build also shows its commit")
    func commit() {
        let info = ["CFBundleShortVersionString": "2.0.0", "CFBundleVersion": "20261102.1200", "KV4PCommit": "abc1234"]
        #expect(AboutInfo(info: info).version == "Version 2.0.0 (20261102.1200, abc1234)")
        #expect(
            AboutInfo(info: ["CFBundleShortVersionString": "2.0.0", "CFBundleVersion": "7", "KV4PCommit": ""]).version
                == "Version 2.0.0 (7)"
        )
        #expect(
            AboutInfo(info: ["CFBundleShortVersionString": "2.0.0", "KV4PCommit": "abc1234"]).version
                == "Version 2.0.0 (abc1234)"
        )
    }

    @Test("the components name their licences; bundled licence texts are named once")
    func components() {
        let components = AboutInfo.components
        #expect(components.first?.name == "kv4p HT for Apple platforms")
        #expect(components.first?.licence == .gpl3)
        #expect(components.contains { $0.name == "Codec2 1.2.0" && $0.licence == .lgpl21 })
        #expect(components.contains { $0.name.hasPrefix("esptool flasher stub") && $0.licence == .gpl2OrLater })
        #expect(Set(components.map(\.id)).count == components.count)
        #expect(AboutInfo.Licence.gpl3.textFile == "LICENSE")
        #expect(AboutInfo.Licence.lgpl21.textFile == "COPYING-codec2")
        #expect(AboutInfo.Licence.gpl2OrLater.textFile == "LICENSE")  // GPL-2.0 or later, used under GPL-3.0
        #expect(AboutInfo.Licence.allCases.allSatisfy { !$0.title.isEmpty })
        #expect(AboutInfo.sourceAddress == "https://github.com/cookieBerlin/kv4p-ht")
    }
}
