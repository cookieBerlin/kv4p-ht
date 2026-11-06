import KV4PAudio
import KV4PPersistence
import Testing

@testable import KV4PRadio

/// A controller that sends the snapshots the test gives it, and does nothing else.
actor ScriptedController: RadioControlling {
    nonisolated let snapshots: AsyncStream<RadioSnapshot>
    nonisolated let receivedFrames: AsyncStream<[UInt8]>
    nonisolated let sent: AsyncStream<RadioSnapshot>.Continuation
    private(set) var snapshot = RadioSnapshot(
        status: .disconnected,
        desired: DesiredStateController().desired,
        isInSync: false
    )

    init() {
        (snapshots, sent) = AsyncStream.makeStream()
        receivedFrames = AsyncStream { $0.finish() }
    }

    /// A ready radio, counted by `revision`.
    nonisolated static func ready(_ revision: Int) -> RadioSnapshot {
        var snapshot = RadioSnapshot(status: .ready, desired: DesiredStateController().desired, isInSync: true)
        snapshot.revision = revision
        return snapshot
    }

    func connect() async {
        snapshot = Self.ready(1)
        sent.yield(snapshot)
    }

    func disconnect() async {}
    func tune(rx: Float, tx: Float, memoryId: Int32) throws(RadioError) {}
    func update(_ changes: @Sendable (inout DesiredStateController) -> Void) {}
    func setMicGain(_ gain: MicGain) {}
    func setTXLimits(_ limits: TXLimits) {}
    func prepareMicrophone() {}
    func setFreeDV(_ on: Bool) {}
    func startTransmitting() async throws(RadioError) {}
    func stopTransmitting() {}
    func tune(to memory: ChannelMemory) throws(RadioError) {}
    func transmitAX25(_ frame: [UInt8], frequency: Float) throws(RadioError) {}
    func sendAccessTone(_ tone: AccessTone) async throws(RadioError) -> AccessToneResult { .finished }
    func startScan(_ memories: [ChannelMemory]) throws(RadioError) {}
    func stopScan() {}
}

@MainActor
@Suite("Radio view model: snapshots after disconnecting")
struct RadioViewModelStaleSnapshotTests {
    @Test("a snapshot that was still on its way when disconnecting is not shown")
    func staleSnapshot() async {
        let controller = ScriptedController()
        let model = RadioViewModel(makeController: { _, _ in controller }, serialDevices: { [] })
        await model.connect()
        #expect(await RadioViewModelTests.eventually(model) { $0.isReady })
        controller.sent.yield(ScriptedController.ready(2))
        controller.sent.yield(ScriptedController.ready(3))
        await model.disconnect()
        for _ in 0..<100 { await Task.yield() }
        #expect(!model.isReady)
    }
}
