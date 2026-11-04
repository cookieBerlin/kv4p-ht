import CryptoKit
import Foundation

/// A firmware the user can write to the radio (ADR-0049).
public struct FirmwareChoice: Identifiable, Equatable, Sendable {
    public enum Edition: Sendable {
        /// The nightly build, whose voice and connections suit this app.
        case forThisApp
        /// Firmware 17 as released, for going back to the Android app.
        case forAndroid
    }

    /// Where a nightly image comes from.
    public struct Build: Codable, Equatable, Sendable {
        public var commit: String
        /// When it was built, e.g. `2026-10-17 07:52 UTC`.
        public var built: String

        public init(commit: String, built: String) {
            self.commit = commit
            self.built = built
        }
    }

    public static let nightlyFileName = "firmware-nightly.bin"
    public static let nightlyManifestName = "firmware-nightly.json"

    public let edition: Edition
    public let images: FirmwareImages
    /// Of the app image, in lowercase hexadecimal.
    public let sha256: String
    public let build: Build?

    public var id: Edition { edition }

    public init(edition: Edition, images: FirmwareImages, sha256: String, build: Build? = nil) {
        self.edition = edition
        self.images = images
        self.sha256 = sha256
        self.build = build
    }

    /// The firmwares in `directory`, the one for this app first. Both share the regions of the Android firmware; a
    /// nightly image is left out if it does not match the checksum of its manifest.
    public static func bundled(in directory: URL) -> [FirmwareChoice] {
        guard let android = FirmwareImages.packaged(in: directory) else { return [] }
        let forAndroid = FirmwareChoice(edition: .forAndroid, images: android, sha256: hash(android.app))
        return [nightly(in: directory, regions: android), forAndroid].compactMap(\.self)
    }

    private struct Manifest: Decodable {
        var commit: String
        var built: String
        var sha256: String
    }

    private static func nightly(in directory: URL, regions: FirmwareImages) -> FirmwareChoice? {
        guard let image = FileManager.default.contents(atPath: directory.appending(path: nightlyFileName).path),
            let manifest = FileManager.default.contents(atPath: directory.appending(path: nightlyManifestName).path),
            let decoded = try? JSONDecoder().decode(Manifest.self, from: manifest),
            hash(Array(image)) == decoded.sha256
        else { return nil }
        var images = regions
        images.app = Array(image)
        return FirmwareChoice(
            edition: .forThisApp,
            images: images,
            sha256: decoded.sha256,
            build: Build(commit: decoded.commit, built: decoded.built)
        )
    }

    private static func hash(_ bytes: [UInt8]) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}
