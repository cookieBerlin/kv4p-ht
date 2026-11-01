import KV4PProtocol

/// What the About window shows: version and build, and the licences of what the app contains or ports.
public struct AboutInfo: Sendable {
    public enum Licence: CaseIterable, Sendable {
        case gpl3, gpl2OrLater, lgpl21

        public var title: String {
            switch self {
            case .gpl3: "GNU GPL 3.0"
            case .gpl2OrLater: "GNU GPL 2.0 or later"
            case .lgpl21: "GNU LGPL 2.1"
            }
        }

        /// The licence text in the app bundle; GPL-2.0-or-later code is used under GPL-3.0.
        public var textFile: String {
            switch self {
            case .gpl3, .gpl2OrLater: "LICENSE"
            case .lgpl21: "COPYING-codec2"
            }
        }
    }

    public struct Component: Sendable, Identifiable {
        public let name: String
        public let licence: Licence
        public let note: String

        public var id: String { name }
    }

    /// The project, where the source code of every version is published.
    public static let sourceAddress = "https://github.com/cookieBerlin/kv4p-ht"

    /// The app first; then what it contains, then what it ports.
    public static let components = [
        Component(name: "kv4p HT for Apple platforms", licence: .gpl3, note: "Source code: \(sourceAddress)"),
        Component(name: "Codec2 1.2.0", licence: .lgpl21, note: "FreeDV voice codec, included unmodified"),
        Component(
            name: "esptool flasher stub 1.4.0",
            licence: .gpl2OrLater,
            note: "Runs on the radio while flashing, included unmodified"
        ),
        Component(name: "kv4p HT Android app", licence: .gpl3, note: "Protocol, audio and radio logic, ported"),
        Component(name: "java-aprs", licence: .gpl3, note: "APRS parsing, messaging and APRS-IS, ported"),
        Component(name: "javAX25", licence: .gpl2OrLater, note: "AX.25 frames, ported"),
        Component(name: "esp32-flash-lib", licence: .gpl3, note: "ESP32 bootloader protocol, ported"),
    ]

    public let version: String
    public let firmware = "Firmware \(KV4P.packagedFirmwareVersion) for USB updates"

    /// `info`: the bundle's info dictionary.
    public init(info: [String: Any]) {
        guard let version = info["CFBundleShortVersionString"] as? String else {
            self.version = "Version unknown"
            return
        }
        // Only release builds know their commit (ADR-0037).
        let details = [info["CFBundleVersion"], info["KV4PCommit"]].compactMap { $0 as? String }.filter { !$0.isEmpty }
        self.version = "Version \(version)" + (details.isEmpty ? "" : " (\(details.joined(separator: ", ")))")
    }
}
