import Foundation

/// The units of the APRS list (ADR-0055). The system decides by its region, where Britain mixes them; pressure is in hPa
/// everywhere.
public enum APRSUnits: String, CaseIterable, Codable, Sendable {
    case system, metric, imperial

    public var label: String {
        switch self {
        case .system: "System"
        case .metric: "Metric"
        case .imperial: "Imperial"
        }
    }

    public func temperature(_ fahrenheit: Double, locale: Locale) -> String {
        usesCelsius(locale)
            ? "\(Self.number((fahrenheit - 32) * 5 / 9, locale)) °C" : "\(Self.number(fahrenheit, locale)) °F"
    }

    public func speed(mph: Double, locale: Locale) -> String {
        usesKilometres(locale)
            ? "\(Self.number(mph * Self.kilometresPerMile, locale, digits: 0)) km/h"
            : "\(Self.number(mph, locale, digits: 0)) mph"
    }

    public func distance(meters: Double, locale: Locale) -> String {
        usesKilometres(locale)
            ? "\(Self.number(meters / 1000, locale)) km"
            : "\(Self.number(meters / 1000 / Self.kilometresPerMile, locale)) mi"
    }

    public func rain(inches: Double, locale: Locale) -> String {
        usesMillimetres(locale) ? "\(Self.number(inches * 25.4, locale)) mm" : "\(Self.number(inches, locale)) in"
    }

    public func snow(inches: Double, locale: Locale) -> String {
        usesMillimetres(locale) ? "\(Self.number(inches * 2.54, locale)) cm" : "\(Self.number(inches, locale)) in"
    }

    private static let kilometresPerMile = 1.609344

    private func usesCelsius(_ locale: Locale) -> Bool {
        self == .metric || (self == .system && locale.measurementSystem != .us)
    }

    private func usesKilometres(_ locale: Locale) -> Bool {
        self == .metric || (self == .system && locale.measurementSystem == .metric)
    }

    private func usesMillimetres(_ locale: Locale) -> Bool {
        usesCelsius(locale)
    }

    static func number(_ value: Double, _ locale: Locale, digits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(0...digits)).grouping(.never).locale(locale))
    }
}
