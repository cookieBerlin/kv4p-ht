package io.github.dkaukov.aprs;

/** Opens the package-private APRS-IS login helpers of java-aprs to the vector generator. */
public final class AprsIsAccess {
    private AprsIsAccess() {}

    public static int passcode(String callsign) {
        return AprsIsClient.passcode(callsign);
    }

    public static String loginLine(String callsign, int passcode, boolean receive, Double latitude, Double longitude,
                                   double radiusKm) {
        return AprsIsClient.loginLine(callsign, passcode, "kv4p-ht", "1.0", receive, latitude, longitude, radiusKm);
    }
}
