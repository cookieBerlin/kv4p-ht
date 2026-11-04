import KV4PFlasher

/// Runs a firmware update of the simulator like a real one, so that its screens can be tried without a radio.
struct SimulatedFirmwareFlasher: FirmwareFlashing {
    let step: Duration

    func flash(serialPath: String, events: @Sendable (FlashEvent) -> Void) async throws(FlashError) {
        events(.connected)
        for percent in stride(from: 0, through: 100, by: 10) {
            try? await Task.sleep(for: step)
            events(.progress(percent))
        }
    }
}
