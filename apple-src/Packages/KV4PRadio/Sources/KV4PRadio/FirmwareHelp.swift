/// Where to update the firmware when the app cannot (iOS has no access to the radio's USB port).
public enum FirmwareHelp {
    /// The project's web flasher, which runs in a desktop browser with the radio on USB.
    public static let webFlasherAddress = "https://kv4p.com/firmware.html"
    public static let manualAddress = AboutInfo.sourceAddress + "/blob/main/docs/apple/manual.md#firmware-updates"
}
