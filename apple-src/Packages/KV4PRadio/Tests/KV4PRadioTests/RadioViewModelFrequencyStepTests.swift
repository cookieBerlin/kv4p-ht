import KV4PAudio
import KV4PPersistence
import KV4PProtocol
import KV4PSimulator
import KV4PTestSupport
import Testing

@testable import KV4PRadio

/// A ready radio that records the tunes and applies one only when the test lets it answer.
actor SlowTuningController: RadioControlling {
    nonisolated let snapshots: AsyncStream<RadioSnapshot>
    nonisolated let receivedFrames: AsyncStream<[UInt8]>
    private nonisolated let sent: AsyncStream<RadioSnapshot>.Continuation
    private(set) var tunes: [Float] = []
    private(set) var snapshot: RadioSnapshot
    private var desired = DesiredStateController()

    init() {
        (snapshots, sent) = AsyncStream.makeStream()
        receivedFrames = AsyncStream { $0.finish() }
        let firmware = FirmwareVersion(
            version: 17,
            radioModuleStatus: .found,
            windowSize: 1024,
            moduleType: .sa818VHF,
            minRadioFreq: 134,
            maxRadioFreq: 174,
            features: []
        )
        desired.attach()
        desired.seed(RadioSimulator(scenario: .ble).deviceState)
        desired.seed(firmware)
        desired.markReady()
        snapshot = RadioSnapshot(
            status: .ready,
            firmware: firmware,
            deviceState: desired.deviceState,
            desired: desired.desired,
            isInSync: true
        )
    }

    func connect() async { sent.yield(snapshot) }

    func tune(rx: Float, tx: Float, memoryId: Int32) throws(RadioError) {
        tunes.append(rx)
        desired.setRxFrequency(rx)
        desired.setTxFrequency(tx)
        snapshot.desired = desired.desired
        snapshot.isInSync = false
        snapshot.revision += 1
        sent.yield(snapshot)
    }

    /// A report of the frequency the radio still has, then the radio applies the last tune.
    func answer() {
        snapshot.revision += 1
        sent.yield(snapshot)
        snapshot.deviceState?.radio.freqRx = snapshot.desired.freqRx
        snapshot.isInSync = true
        snapshot.revision += 1
        sent.yield(snapshot)
    }

    func disconnect() async {}
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

/// Stepping the frequency digit by digit (ADR-0064).
@MainActor
@Suite("Radio view model: frequency steps")
struct RadioViewModelFrequencyStepTests {
    func eventually(_ model: RadioViewModel, _ condition: (RadioViewModel) -> Bool) async -> Bool {
        await RadioViewModelTests.eventually(model, condition)
    }

    func connected() async -> RadioViewModel {
        let model = RadioViewModelTests.model()
        await model.connect()
        #expect(await eventually(model) { $0.isReady && $0.snapshot.isInSync })
        return model
    }

    @Test("a step tunes the radio at once")
    func step() async {
        let model = await connected()
        #expect(model.canStepFrequency)
        await model.stepFrequency(digit: 100_000, by: 1)
        #expect(model.frequencyText == "144.1000")
        #expect(await eventually(model) { $0.snapshot.isInSync && $0.snapshot.deviceState?.radio.freqRx == 144.1 })
        #expect(model.frequencyText == "144.1000")
    }

    @Test("a small digit steps by the raster of the bandwidth, exactly by itself")
    func raster() async {
        let model = await connected()
        model.isWideBandwidth = false
        #expect(await eventually(model) { $0.snapshot.isInSync })
        await model.stepFrequency(digit: 100, by: 1)
        #expect(model.frequencyText == "144.0125")
        model.isWideBandwidth = true
        #expect(await eventually(model) { $0.snapshot.isInSync })
        await model.stepFrequency(digit: 100, by: -1)
        #expect(model.frequencyText == "144.0000")
        await model.stepFrequency(digit: 100, by: 1, exact: true)
        #expect(model.frequencyText == "144.0001")
    }

    @Test("a step at the limit changes nothing")
    func limit() async {
        let model = await connected()
        await model.stepFrequency(digit: 1_000_000, by: -1)
        #expect(model.frequencyText == "144.0000")
        await model.stepFrequency(digit: 100_000_000, by: -1)
        #expect(model.frequencyText == "134.0000")
        #expect(await eventually(model) { $0.snapshot.isInSync })
        await model.stepFrequency(digit: 100_000_000, by: -1)
        #expect(model.frequencyText == "134.0000")
    }

    @Test("steps faster than the radio answers send only the latest, and the shown frequency stays")
    func coalesced() async {
        let controller = SlowTuningController()
        let model = RadioViewModel(makeController: { _, _ in controller }, serialDevices: { [] })
        await model.connect()
        #expect(await eventually(model) { $0.isReady && $0.frequencyText == "144.0000" })
        for _ in 0..<5 {
            await model.stepFrequency(digit: 100_000, by: 1)
        }
        #expect(model.frequencyText == "144.5000")
        #expect(await controller.tunes == [144.1])
        await controller.answer()
        #expect(await KV4PTestSupport.eventually { await controller.tunes == [144.1, 144.5] })
        #expect(model.frequencyText == "144.5000")
        await controller.answer()
        for _ in 0..<100 { await Task.yield() }
        #expect(await controller.tunes == [144.1, 144.5])
        #expect(model.frequencyText == "144.5000")
    }

    @Test("an entered frequency replaces a step that waits")
    func enteredReplacesWaiting() async {
        let model = await connected()
        await model.stepFrequency(digit: 100_000, by: 1)
        await model.stepFrequency(digit: 100_000, by: 1)
        model.frequencyText = "146.52"
        await model.applyFrequency()
        #expect(await eventually(model) { $0.snapshot.isInSync && $0.snapshot.deviceState?.radio.freqRx == 146.52 })
        for _ in 0..<100 { await Task.yield() }
        #expect(model.snapshot.deviceState?.radio.freqRx == 146.52)
        #expect(model.frequencyText == "146.5200")
    }

    @Test("no steps while transmitting or not connected")
    func blocked() async {
        let model = RadioViewModelTests.model()
        #expect(!model.canStepFrequency)
        await model.stepFrequency(digit: 100_000, by: 1)
        #expect(model.frequencyText == "")
        let setup = RadioViewModelTransmitTests.Setup()
        await setup.tuned()
        await setup.model.pressPTT()
        #expect(!setup.model.canStepFrequency)
        await setup.model.stepFrequency(digit: 100_000, by: 1)
        #expect(setup.model.frequencyText == "146.5200")
        await setup.model.releasePTT()
        #expect(setup.model.canStepFrequency)
    }

    @Test("frequencies show the decimal separator of the user's language")
    func separator() async {
        let model = RadioViewModelTests.model()
        model.decimalSeparator = ","
        await model.connect()
        #expect(await eventually(model) { $0.isReady && $0.snapshot.isInSync })
        #expect(model.frequencyText == "144,0000")
        #expect(model.shown(146.52) == "146,5200")
        model.frequencyText = "146,52"
        await model.applyFrequency()
        #expect(model.frequencyText == "146,5200")
        await model.stepFrequency(digit: 100_000, by: 1)
        #expect(model.frequencyText == "146,6200")
        var memory = ChannelMemory(name: "N0CALL", frequency: 146.94)
        memory.offset = .down
        memory.offsetKHz = 600
        #expect(model.transmitText(for: memory) == "Transmits on 146,3400 MHz")
        #expect(
            model.memoryProblem(ChannelMemory(name: "N0CALL", frequency: 440))
                == "This radio receives from 134,0000 to 174,0000 MHz."
        )
        model.isWideBandwidth = false
        model.frequencyText = "150"
        await model.applyFrequency()
        #expect(await eventually(model) { $0.snapshot.isInSync && !$0.canTransmit })
        model.callsign = "N0CALL"
        #expect(
            model.transmitBlockedText?.hasPrefix("Can't transmit here: with 12,5 kHz, the allowed range is 144,")
                == true
        )
    }
}
