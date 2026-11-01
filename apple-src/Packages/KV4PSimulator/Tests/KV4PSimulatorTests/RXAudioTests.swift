import KV4PAudio
import Testing

@testable import KV4PProtocol
@testable import KV4PSimulator

/// RX audio and squelch: the firmware streams one ADPCM block per 249 samples to sessions with `RX_AUDIO_OPEN`.
@Suite("Simulator RX audio")
struct RXAudioTests {
    /// A connected device with RX audio open at time zero, and its output.
    static func listening(_ scenario: Scenario = Scenario(), flags: StateFlags = [.rxAudioOpen]) -> RadioSimulator {
        var simulator = RadioSimulator(scenario: scenario)
        _ = simulator.connect(at: .zero)
        _ = simulator.receive(FrameEncoder.desiredState(desiredState(sequence: 1, flags: flags)), at: .zero)
        return simulator
    }

    static func decoded(_ blocks: [[UInt8]]) -> [Int16] {
        blocks.flatMap { ImaAdpcm.decodeBlock($0, maxSamples: KV4P.audioBlockSamples) }
    }

    @Test("a block of 249 samples is sent every 15.5625 ms")
    func cadence() throws {
        var simulator = Self.listening()
        let blocks = try events(simulator.advance(to: .seconds(1))).audioBlocks
        #expect(blocks.count == 64)  // 64 × 15.5625 ms = 996 ms
        #expect(blocks.allSatisfy { $0.count == ImaAdpcm.encodedSize(samples: KV4P.audioBlockSamples) })
        #expect(try events(simulator.advance(to: .milliseconds(1011))).audioBlocks.count == 0)
        #expect(try events(simulator.advance(to: .milliseconds(1012))).audioBlocks.count == 1)
    }

    @Test("without a carrier the squelch is closed and the audio muted")
    func squelched() throws {
        var simulator = Self.listening()
        let output = try events(simulator.advance(to: .milliseconds(100)))
        #expect(Self.decoded(output.audioBlocks).allSatisfy { $0 == 0 })
        #expect(simulator.deviceState.radio.flags.contains(.squelched))
        #expect(simulator.deviceState.latestRssi == 0)
    }

    @Test("a carrier opens the squelch and plays its tone")
    func carrier() throws {
        var scenario = Scenario()
        scenario.carrier = Carrier(toneHz: 1000, amplitude: 8000, rssi: 120)
        var simulator = Self.listening(scenario, flags: [.rxAudioOpen, .rssiEnabled])
        let samples = Self.decoded(try events(simulator.advance(to: .seconds(1))).audioBlocks)
        #expect(!simulator.deviceState.radio.flags.contains(.squelched))
        #expect(simulator.deviceState.latestRssi == 120)
        let peak = samples.map { abs(Int($0)) }.max() ?? 0
        #expect((7200...8800).contains(peak))
        // 1 kHz crosses zero upwards once per millisecond.
        let crossings = zip(samples, samples.dropFirst()).filter { $0 < 0 && $1 >= 0 }.count
        #expect((990...1000).contains(crossings))
    }

    @Test("the RSSI is reported only with RSSI_ENABLED")
    func rssiDisabled() {
        var scenario = Scenario()
        scenario.carrier = Carrier()
        let simulator = Self.listening(scenario)
        #expect(simulator.deviceState.latestRssi == 0)
        #expect(!simulator.deviceState.radio.flags.contains(.squelched))
    }

    @Test("a carrier that starts later opens the squelch and reports the state")
    func carrierStarts() throws {
        var simulator = Self.listening()
        _ = simulator.advance(to: .milliseconds(100))
        let output = try events(simulator.setCarrier(Carrier(), at: .milliseconds(120)))
        #expect(output.states.last.map { !$0.radio.flags.contains(.squelched) } == true)
        let ended = try events(simulator.setCarrier(nil, at: .milliseconds(140)))
        #expect(ended.states.last.map { $0.radio.flags.contains(.squelched) } == true)
        #expect(try events(simulator.setCarrier(nil, at: .milliseconds(141))).states.isEmpty)
    }

    @Test("no audio without RX_AUDIO_OPEN or while disconnected")
    func noAudio() throws {
        var closed = Self.listening(flags: [])
        #expect(try events(closed.advance(to: .seconds(1))).audioBlocks.isEmpty)
        var disconnected = Self.listening()
        _ = disconnected.disconnect(at: .milliseconds(10))
        #expect(try events(disconnected.advance(to: .seconds(1))).audioBlocks.isEmpty)
    }

    @Test("no audio during TX; it resumes afterwards at its own cadence")
    func noAudioDuringTX() throws {
        var simulator = Self.listening(flags: [.rxAudioOpen, .txAllowed])
        _ = simulator.receive(
            FrameEncoder.desiredState(desiredState(sequence: 2, flags: [.rxAudioOpen, .txAllowed, .pttRequested])),
            at: .milliseconds(5)
        )
        // The TX watchdog ends TX after 778 ms without TX audio.
        let tx = try events(simulator.advance(to: .milliseconds(783)))
        #expect(tx.audioBlocks.isEmpty)
        #expect(try events(simulator.advance(to: .milliseconds(799))).audioBlocks.count == 1)
    }
}
