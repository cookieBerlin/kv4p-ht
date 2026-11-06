/// Where to update the firmware when the app cannot (iOS has no access to the radio's USB port). The project's web
/// flasher is no help: it writes only firmware 17, which this app refuses (ADR-0049).
public enum FirmwareHelp {
    public static let manualAddress = AboutInfo.sourceAddress + "/blob/main/docs/apple/manual.md#firmware-updates"
}
