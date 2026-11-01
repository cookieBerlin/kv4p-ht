/// Weather data (java-aprs `WeatherField`), as `WeatherParser` finds it anywhere after the position.
public struct WeatherField: Equatable, Sendable {
    public internal(set) var windDirection: Int?
    public internal(set) var windSpeed: Int?
    public internal(set) var windGust: Int?
    /// °F.
    public internal(set) var temperature: Int?
    /// Inches.
    public internal(set) var rainLastHour: Double?
    public internal(set) var rainLast24Hours: Double?
    public internal(set) var rainSinceMidnight: Double?
    /// Percent; `h00` means 100 %.
    public internal(set) var humidity: Double?
    /// Hectopascal.
    public internal(set) var pressure: Double?
    public internal(set) var luminosity: Int?
    public internal(set) var snowfallLast24Hours: Double?
}

/// java-aprs `WeatherParser`: one regular expression per value, with Java's greedy matching.
enum WeatherParser {
    nonisolated(unsafe) private static let wind = /(?:^|_)(\d{3})\/(\d{3})/
    nonisolated(unsafe) private static let gust = /.*g(\d{3}).*./
    nonisolated(unsafe) private static let temperature = /.*t(-?\d{2,3}).*/
    nonisolated(unsafe) private static let rain = /.*r(\d{3}).*/
    nonisolated(unsafe) private static let rain24 = /.*p(\d{3}).*/
    nonisolated(unsafe) private static let rainMidnight = /.*P(\d{3}).*/
    nonisolated(unsafe) private static let humidity = /.*h(\d{2}).*/
    nonisolated(unsafe) private static let pressure = /.*b(\d{5}).*/
    nonisolated(unsafe) private static let luminosityLow = /.*L(\d{3}).*/
    nonisolated(unsafe) private static let luminosityHigh = /.*l(\d{3}).*/
    nonisolated(unsafe) private static let snow = /.*s(\d{3}).*/

    static func parse(_ body: [UInt8], cursor: Int) -> WeatherField {
        let report = Java.ascii(body[cursor...])
        var weather = WeatherField()
        if let match = report.firstMatch(of: wind.asciiOnlyDigits()) {
            weather.windDirection = Java.parseInt(match.1)
            weather.windSpeed = Java.parseInt(match.2)
        }
        weather.windGust = integer(gust, in: report)
        weather.temperature = integer(temperature, in: report)
        weather.rainLastHour = decimal(rain, in: report).map { $0 / 100 }
        weather.rainSinceMidnight = decimal(rainMidnight, in: report).map { $0 / 100 }
        weather.rainLast24Hours = decimal(rain24, in: report).map { $0 / 100 }
        weather.humidity = decimal(humidity, in: report).map { $0 == 0 ? 100 : $0 }
        weather.pressure = decimal(pressure, in: report).map { $0 / 10 }
        weather.luminosity = integer(luminosityLow, in: report)
        if let high = integer(luminosityHigh, in: report) {
            weather.luminosity = high + 1000
        }
        weather.snowfallLast24Hours = decimal(snow, in: report)
        return weather
    }

    private static func integer(_ pattern: Regex<(Substring, Substring)>, in report: String) -> Int? {
        report.firstMatch(of: pattern.asciiOnlyDigits()).flatMap { Java.parseInt($0.1) }
    }

    private static func decimal(_ pattern: Regex<(Substring, Substring)>, in report: String) -> Double? {
        report.firstMatch(of: pattern.asciiOnlyDigits()).flatMap { Double($0.1) }
    }
}
