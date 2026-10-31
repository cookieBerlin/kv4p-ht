/// Converts the raw SA818 RSSI to S-meter bars like `Protocol.calculateSMeterValue`
/// (`docs/apple/03-protocol-spec.md` §4.2).
public enum SMeter {
    /// Bar 13 means RX overload.
    public static let overload = 13

    private static let dbmPerRssi: Float = 1.2
    private static let rssiDbmOffset: Float = -160.8
    private static let s1Dbm: Float = -141
    private static let s9Dbm: Float = -93
    private static let overloadDbm: Float = -30

    /// 0 below S1, 1…9 in 6 dB steps, 10…12 in 20 dB steps above S9, 13 for overload.
    public static func value(rssi: UInt8) -> Int {
        let dbm = Float(rssi) * dbmPerRssi + rssiDbmOffset
        if dbm > overloadDbm { return overload }
        if dbm < s1Dbm { return 0 }
        if dbm <= s9Dbm { return min(9, 1 + Int(((dbm - s1Dbm) / 6).rounded(.down))) }
        return min(12, 9 + Int(((dbm - s9Dbm) / 20).rounded(.down)))
    }
}
