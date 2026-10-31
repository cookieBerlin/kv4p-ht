/// Host and device state flags (`docs/apple/03-protocol-spec.md` §4.4).
public struct StateFlags: OptionSet, Hashable, Sendable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let radioConfigValid = StateFlags(rawValue: 1 << 0)
    public static let pttRequested = StateFlags(rawValue: 1 << 1)
    /// Session scope: stream RX audio to this session.
    public static let rxAudioOpen = StateFlags(rawValue: 1 << 2)
    public static let highPower = StateFlags(rawValue: 1 << 3)
    public static let rssiEnabled = StateFlags(rawValue: 1 << 4)
    public static let filterPre = StateFlags(rawValue: 1 << 5)
    public static let filterHigh = StateFlags(rawValue: 1 << 6)
    public static let filterLow = StateFlags(rawValue: 1 << 7)
    /// Device only.
    public static let physicalPTTDown = StateFlags(rawValue: 1 << 8)
    /// Device only.
    public static let txActive = StateFlags(rawValue: 1 << 9)
    /// Device only.
    public static let squelched = StateFlags(rawValue: 1 << 10)
    public static let txAllowed = StateFlags(rawValue: 1 << 11)
    /// Session scope: the device sends `DEVICE_STATE` periodically and on changes.
    public static let enableStatusReports = StateFlags(rawValue: 1 << 12)
    /// Host only.
    public static let freeDV2400B = StateFlags(rawValue: 1 << 13)
}
