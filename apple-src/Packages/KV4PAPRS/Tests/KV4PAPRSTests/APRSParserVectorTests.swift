import KV4PTestSupport
import Testing

@testable import KV4PAPRS

/// Checks `APRSParser` against java-aprs `Parser.parseAX25`, the parser of the Android app.
@Suite("APRS parser vectors")
struct APRSParserVectorTests {
    struct Input: Decodable, Sendable {
        let frame: String
    }

    struct PositionJSON: Decodable, Sendable, Equatable {
        let latitude: Double
        let longitude: Double
        let ambiguity: Int
        let symbolTable: String
        let symbolCode: String
        let source: String
        let comment: String?
        let hasFault: Bool
    }

    struct MessageJSON: Decodable, Sendable, Equatable {
        let target: String
        let body: String?
        let number: String?
        let ack: Bool
        let rej: Bool
        let hasFault: Bool
    }

    struct WeatherJSON: Decodable, Sendable, Equatable {
        let windDirection: Int?
        let windSpeed: Int?
        let windGust: Int?
        let temp: Int?
        let rainLastHour: Double?
        let rainLast24Hours: Double?
        let rainSinceMidnight: Double?
        let humidity: Double?
        let pressure: Double?
        let luminosity: Int?
        let snowfallLast24Hours: Double?
        let comment: String?
    }

    struct ObjectJSON: Decodable, Sendable, Equatable {
        let name: String
        let live: Bool
        let comment: String?
        let position: PositionJSON
    }

    struct CapabilitiesJSON: Decodable, Sendable, Equatable {
        let displayText: String
        let igate: Bool
        let messageCount: Int?
        let localStationCount: Int?
    }

    final class PacketJSON: Decodable, Sendable, Equatable {
        let error: Bool?
        let source: String?
        let destination: String?
        let digipeaters: [String]?
        let dti: String?
        let hasFault: Bool?
        let comment: String?
        let infoComment: String?
        let types: [String]?
        let message: MessageJSON?
        let position: PositionJSON?
        let weather: WeatherJSON?
        let object: ObjectJSON?
        let status: String?
        let capabilities: CapabilitiesJSON?
        let thirdParty: PacketJSON?

        init(_ packet: APRSPacket) {
            let info = packet.info
            error = nil
            source = packet.source
            destination = packet.destination
            digipeaters = packet.digipeaters.map(\.description)
            dti = Java.latin1([packet.dti])
            hasFault = packet.hasFault
            comment = packet.comment
            infoComment = info.comment
            types = APRSDataType.allCases.filter(info.types.contains).map(\.rawValue)
            message = info.message.map {
                MessageJSON(
                    target: $0.target,
                    body: $0.body,
                    number: $0.number,
                    ack: $0.isAck,
                    rej: $0.isRej,
                    hasFault: $0.hasFault
                )
            }
            position = info.position.map(Self.position)
            weather = info.weather.map {
                WeatherJSON(
                    windDirection: $0.windDirection,
                    windSpeed: $0.windSpeed,
                    windGust: $0.windGust,
                    temp: $0.temperature,
                    rainLastHour: $0.rainLastHour,
                    rainLast24Hours: $0.rainLast24Hours,
                    rainSinceMidnight: $0.rainSinceMidnight,
                    humidity: $0.humidity,
                    pressure: $0.pressure,
                    luminosity: $0.luminosity,
                    snowfallLast24Hours: $0.snowfallLast24Hours,
                    comment: nil
                )
            }
            object = info.object.map {
                ObjectJSON(name: $0.name, live: $0.isLive, comment: $0.comment, position: Self.position($0.position))
            }
            status = info.status?.text
            capabilities = info.capabilities.map {
                CapabilitiesJSON(
                    displayText: $0.displayText,
                    igate: $0.isIGate,
                    messageCount: $0.messageCount,
                    localStationCount: $0.localStationCount
                )
            }
            thirdParty = info.thirdParty.map(PacketJSON.init)
        }

        private static func position(_ field: PositionField) -> PositionJSON {
            PositionJSON(
                latitude: field.position.latitude,
                longitude: field.position.longitude,
                ambiguity: field.position.ambiguity,
                symbolTable: Java.string(field.position.symbolTable),
                symbolCode: Java.string(field.position.symbolCode),
                source: field.source,
                comment: field.comment,
                hasFault: field.hasFault
            )
        }

        static func == (lhs: PacketJSON, rhs: PacketJSON) -> Bool {
            lhs.error == rhs.error && lhs.source == rhs.source && lhs.destination == rhs.destination
                && lhs.digipeaters == rhs.digipeaters && lhs.dti == rhs.dti && lhs.hasFault == rhs.hasFault
                && lhs.comment == rhs.comment && lhs.infoComment == rhs.infoComment && lhs.types == rhs.types
                && lhs.message == rhs.message && lhs.position == rhs.position && lhs.weather == rhs.weather
                && lhs.object == rhs.object && lhs.status == rhs.status && lhs.capabilities == rhs.capabilities
                && lhs.thirdParty == rhs.thirdParty
        }
    }

    typealias Vector = VectorFile<Input, PacketJSON>.Vector

    static let vectors = (try? VectorFile<Input, PacketJSON>.load("aprs-parser", from: .module)) ?? []

    @Test("vector file is present")
    func vectorsPresent() {
        #expect(Self.vectors.count > 100)
    }

    @Test("parses like Android", arguments: vectors)
    func parsesLikeAndroid(vector: Vector) throws {
        let frame = try [UInt8](hex: vector.input.frame)
        if vector.expected.error == true {
            #expect(throws: APRSParseError.invalidFrame) { try APRSParser.parse(ax25: frame) }
        } else {
            #expect(PacketJSON(try APRSParser.parse(ax25: frame)) == vector.expected)
        }
    }
}
