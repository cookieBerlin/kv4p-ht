/// Encodes device → host frames like the firmware; used by the simulator.
public enum DeviceFrameEncoder {
    public static func hello(_ hello: Hello) -> [UInt8] {
        vendor(.hello, hello.encoded())
    }

    public static func deviceState(_ state: DeviceState) -> [UInt8] {
        vendor(.deviceState, state.encoded())
    }

    public static func windowUpdate(_ update: WindowUpdate) -> [UInt8] {
        vendor(.windowUpdate, update.encoded())
    }

    /// One IMA ADPCM block of received audio.
    public static func rxAudio(_ block: [UInt8]) -> [UInt8] {
        vendor(.rxAudio, block)
    }

    /// One Codec2 1300 frame received in FreeDV 2400B mode.
    public static func rxDigital(_ frame: [UInt8]) -> [UInt8] {
        vendor(.rxDigital, frame)
    }

    /// KISS DATA frame carrying a received AX.25 packet without FCS.
    public static func ax25(_ packet: [UInt8]) -> [UInt8] {
        KISS.frame(command: KISS.Command.data, payload: packet)
    }

    private static func vendor(_ command: DeviceCommand, _ payload: [UInt8]) -> [UInt8] {
        KV4P.vendorFrame(command.rawValue, payload)
    }
}
