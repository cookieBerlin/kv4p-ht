/// BLE GATT service of the firmware (`BluedroidBleKissGattStream.h`, `docs/apple/03-protocol-spec.md` §1.1).
public enum BLEGATT {
    public static let serviceUUID = "00000001-ba2a-46c9-ae49-01b0961f68bb"
    /// Host → device: Write and Write Without Response.
    public static let txCharacteristicUUID = "00000002-ba2a-46c9-ae49-01b0961f68bb"
    /// Device → host: Read and Notify. The device sends `HELLO` after the notify subscription.
    public static let rxCharacteristicUUID = "00000003-ba2a-46c9-ae49-01b0961f68bb"
}
