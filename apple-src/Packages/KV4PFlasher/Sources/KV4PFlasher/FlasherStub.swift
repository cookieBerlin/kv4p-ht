import Foundation

/// The esptool flasher stub that esp32-flash-lib loads into the ESP32's RAM (`stubs/1/esp32.json`, GPL-2.0-or-later,
/// copied unchanged by `make vectors`).
public struct FlasherStub: Equatable, Sendable, Decodable {
    public var text: Data
    public var textStart: UInt32
    public var data: Data
    public var dataStart: UInt32
    public var entry: UInt32

    /// The stub for the ESP32 of the kv4p HT.
    public static func esp32() throws -> FlasherStub {
        try load(from: Bundle.module.url(forResource: "esp32-stub", withExtension: "json", subdirectory: "Resources"))
    }

    static func load(from url: URL?) throws -> FlasherStub {
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(FlasherStub.self, from: Data(contentsOf: url))
    }
}
