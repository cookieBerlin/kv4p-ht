import Foundation

/// The esptool flasher stub that esp32-flash-lib loads into the ESP32's RAM (`stubs/1/esp32.json`, GPL-2.0-or-later,
/// embedded unchanged by `make vectors`).
public struct FlasherStub: Equatable, Sendable, Decodable {
    public var text: Data
    public var textStart: UInt32
    public var data: Data
    public var dataStart: UInt32
    public var entry: UInt32

    /// The stub for the ESP32 of the kv4p HT.
    public static func esp32() throws -> FlasherStub {
        try decode(Data(esp32JSON.utf8))
    }

    static func decode(_ json: Data) throws -> FlasherStub {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(FlasherStub.self, from: json)
    }
}
