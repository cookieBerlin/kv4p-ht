import KV4PProtocol

/// Firmware 17 behaviour the simulator reproduces (`microcontroller-src/kv4p_ht_esp32_wroom_32`).
enum Firmware {
    /// `FIRMWARE_VER`.
    static let version: UInt16 = 17
    /// `DEVICE_STATE_REPORT_INTERVAL_MS`.
    static let statusReportInterval = Duration.milliseconds(500)
    /// `TX_AUDIO_TIMEOUT_MS`: 50 audio blocks, truncated to whole milliseconds.
    static let txAudioTimeout = Duration.milliseconds(50 * KV4P.audioBlockSamples * 1000 / KV4P.audioSampleRate)
    /// One `RX_AUDIO` block: 249 samples at 16 kHz, 15.5625 ms.
    static let audioBlockPeriod = Duration.nanoseconds(
        Int64(KV4P.audioBlockSamples) * 1_000_000_000 / Int64(KV4P.audioSampleRate)
    )
    /// One FreeDV 2400B frame: 320 Codec2 samples at 8 kHz.
    static let freeDVFramePeriod = Duration.milliseconds(40)
    /// `RUNAWAY_TX_SEC`; TX stops once it is exceeded.
    static let runawayTX = Duration.seconds(200)
    /// `USB_BUFFER_SIZE`, the window of USB and Bluetooth Classic sessions.
    static let usbWindowSize: UInt32 = 2048
    /// `BLE_KISS_WINDOW_SIZE`.
    static let bleWindowSize: UInt32 = 4096
    /// Flags restored from flash at boot (`persistedStateFlags`).
    static let persistedFlags: StateFlags = [
        .radioConfigValid, .highPower, .rssiEnabled, .filterPre, .filterHigh, .filterLow, .txAllowed,
    ]
}
