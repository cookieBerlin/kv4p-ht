/// USB serial devices that may be a kv4p HT (CP2102 on the board; other ESP32 boards use CH340 or native USB).
public enum SerialDevices {
    private static let usbMarkers = ["usbserial", "SLAB_USBtoUART", "wchusbserial", "usbmodem"]

    /// Call-out devices (`/dev/cu.*`) of USB serial bridges among the entries of `/dev`, sorted.
    public static func candidates(in names: [String]) -> [String] {
        names.filter { name in
            name.hasPrefix("cu.") && usbMarkers.contains { name.contains($0) }
        }
        .sorted()
        .map { "/dev/" + $0 }
    }
}
