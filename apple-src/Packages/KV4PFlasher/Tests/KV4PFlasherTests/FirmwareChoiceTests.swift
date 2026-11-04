import CryptoKit
import Foundation
import KV4PProtocol
import Testing

@testable import KV4PFlasher

/// The firmwares the Mac app offers (ADR-0049).
@Suite("Firmware choice")
struct FirmwareChoiceTests {
    /// A folder like the app's resources, with one-byte images.
    final class Folder {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

        init() throws {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            for (index, name) in FirmwareImages.packagedFileNames.enumerated() {
                try write(name, Data([UInt8(index + 1)]))
            }
        }

        deinit {
            try? FileManager.default.removeItem(at: url)
        }

        func write(_ name: String, _ data: Data) throws {
            try data.write(to: url.appending(path: name))
        }

        /// The nightly image `[9]`, with a manifest that claims `sha256`.
        func writeNightly(sha256: String = FirmwareChoiceTests.nightlyHash) throws {
            try write(FirmwareChoice.nightlyFileName, Data([9]))
            let manifest = #"{"commit":"abcdef1234","built":"2026-10-17 07:52 UTC","sha256":"\#(sha256)"}"#
            try write(FirmwareChoice.nightlyManifestName, Data(manifest.utf8))
        }
    }

    static let nightlyHash = SHA256.hash(data: Data([9])).map { String(format: "%02x", $0) }.joined()

    /// `apple-src/`, from this file's path, for the images in the repository.
    static let appleSource = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test("the nightly build comes first, for this app, with the regions of the Android firmware")
    func both() throws {
        let folder = try Folder()
        try folder.writeNightly()
        let choices = FirmwareChoice.bundled(in: folder.url)
        #expect(choices.map(\.edition) == [.forThisApp, .forAndroid])
        let nightly = try #require(choices.first)
        #expect(nightly.id == .forThisApp)
        #expect(nightly.images == FirmwareImages(bootloader: [1], partitions: [2], bootApp0: [3], app: [9]))
        #expect(nightly.sha256 == Self.nightlyHash)
        #expect(nightly.build == .init(commit: "abcdef1234", built: "2026-10-17 07:52 UTC"))
        let android = try #require(choices.last)
        #expect(android.images == FirmwareImages(bootloader: [1], partitions: [2], bootApp0: [3], app: [4]))
        #expect(android.build == nil)
        #expect(android.sha256 == SHA256.hash(data: Data([4])).map { String(format: "%02x", $0) }.joined())
    }

    @Test("without the regions there is nothing to offer")
    func noRegions() throws {
        let folder = try Folder()
        try folder.writeNightly()
        try FileManager.default.removeItem(at: folder.url.appending(path: "bootloader.bin"))
        #expect(FirmwareChoice.bundled(in: folder.url).isEmpty)
    }

    @Test("a nightly image that does not match its checksum is not offered")
    func wrongChecksum() throws {
        let folder = try Folder()
        try folder.writeNightly(sha256: String(repeating: "0", count: 64))
        #expect(FirmwareChoice.bundled(in: folder.url).map(\.edition) == [.forAndroid])
    }

    @Test("a nightly image without its manifest, or a manifest without the image, is not offered")
    func incomplete() throws {
        let noManifest = try Folder()
        try noManifest.write(FirmwareChoice.nightlyFileName, Data([9]))
        #expect(FirmwareChoice.bundled(in: noManifest.url).map(\.edition) == [.forAndroid])
        let noImage = try Folder()
        try noImage.writeNightly()
        try FileManager.default.removeItem(at: noImage.url.appending(path: FirmwareChoice.nightlyFileName))
        #expect(FirmwareChoice.bundled(in: noImage.url).map(\.edition) == [.forAndroid])
        let invalid = try Folder()
        try invalid.write(FirmwareChoice.nightlyFileName, Data([9]))
        try invalid.write(FirmwareChoice.nightlyManifestName, Data("not json".utf8))
        #expect(FirmwareChoice.bundled(in: invalid.url).map(\.edition) == [.forAndroid])
    }

    /// The real images, copied into one folder as the app's bundle does.
    static func realChoices() throws -> (choices: [FirmwareChoice], folder: Folder) {
        let folder = try Folder()
        let raw = appleSource.deletingLastPathComponent().appending(path: "android-src/KV4PHT/app/src/main/res/raw")
        for name in FirmwareImages.packagedFileNames {
            try folder.write(name, Data(contentsOf: raw.appending(path: name)))
        }
        for name in [FirmwareChoice.nightlyFileName, FirmwareChoice.nightlyManifestName] {
            try folder.write(name, Data(contentsOf: appleSource.appending(path: "App/Firmware/\(name)")))
        }
        return (FirmwareChoice.bundled(in: folder.url), folder)
    }

    /// The size of the app partition `app0` in an ESP32 partition table.
    static func app0Size(_ table: [UInt8]) -> Int? {
        stride(from: 0, to: table.count - 31, by: 32).lazy.compactMap { offset -> Int? in
            let entry = Array(table[offset..<(offset + 32)])
            guard entry[0] == 0xAA, entry[1] == 0x50, entry[12...15].elementsEqual("app0".utf8) else { return nil }
            return entry[8...11].reversed().reduce(0) { $0 << 8 | Int($1) }
        }.first
    }

    @Test("the images in the repository are the ones the app promises")
    func repository() throws {
        let (choices, _) = try Self.realChoices()
        #expect(choices.map(\.edition) == [.forThisApp, .forAndroid])
        let service = Array(BLEGATT.serviceUUID.utf8)
        let adpcm = Array("adpcm".utf8)
        let nightly = try #require(choices.first).images
        let android = try #require(choices.last).images
        #expect(Data(nightly.app).firstRange(of: Data(service)) != nil)
        #expect(Data(nightly.app).firstRange(of: Data(adpcm)) != nil)
        #expect(Data(android.app).firstRange(of: Data(service)) == nil)
        #expect(Data(android.app).firstRange(of: Data(adpcm)) == nil)
        let partition = try #require(Self.app0Size(nightly.partitions))
        #expect(nightly.app.count <= partition)
        #expect(android.app.count <= partition)
        for image in [nightly.app, android.app] {
            #expect(image.first == 0xE9, "the magic byte of an ESP32 app image")
        }
    }
}
