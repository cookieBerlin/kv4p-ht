import KV4PFlasher
import KV4PProtocol

/// What the user reads before choosing a firmware (ADR-0049).
extension FirmwareChoice {
    public var isForThisApp: Bool { edition == .forThisApp }

    public var title: String {
        switch edition {
        case .forThisApp: "Nightly build, for this app"
        case .forAndroid: "Firmware \(KV4P.packagedFirmwareVersion), only for the Android app"
        }
    }

    public var suitability: String {
        switch edition {
        case .forThisApp:
            "Sound, USB and Bluetooth LE work with this app. It is a development build of the kv4p HT project."
        case .forAndroid:
            "For going back to the Android app. This app does not connect to it, as it would have no sound, "
                + "and it has no Bluetooth LE."
        }
    }

    public var details: [String] {
        let origin = build.map { "Built \($0.built), commit \($0.commit.prefix(7))" }
        return [origin, "SHA-256 \(sha256)"].compactMap(\.self)
    }
}
