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

    /// One second of audio from a radio set to `squelch` that receives `signal`.
    static func heard(_ signal: SimulatedSignal, squelch: UInt8 = 0) throws -> (RadioSimulator, [Int16]) {
        var scenario = Scenario()
        scenario.carrier = signal.carrier
        var simulator = RadioSimulator(scenario: scenario)
        _ = simulator.connect(at: .zero)
        var state = desiredState(sequence: 1, flags: [.rxAudioOpen, .rssiEnabled])
        state.squelch = squelch
        _ = simulator.receive(FrameEncoder.desiredState(state), at: .zero)
        return (simulator, decoded(try events(simulator.advance(to: .seconds(1))).audioBlocks))
    }

    @Test("a signal opens the squelch from the set level on, and the S-meter still shows a weaker one")
    func squelchLevel() throws {
        let (open, heard) = try Self.heard(.s5, squelch: 5)
        #expect(!open.deviceState.radio.flags.contains(.squelched))
        #expect(heard.contains { $0 != 0 })
        let (closed, muted) = try Self.heard(.s4, squelch: 5)
        #expect(closed.deviceState.radio.flags.contains(.squelched))
        #expect(closed.deviceState.latestRssi == SimulatedSignal.s4.rssi)
        #expect(muted.allSatisfy { $0 == 0 })
    }

    @Test("squelch 0 stays open even for noise alone")
    func squelchOff() throws {
        let (simulator, heard) = try Self.heard(.s0)
        #expect(!simulator.deviceState.radio.flags.contains(.squelched))
        #expect(heard.contains { $0 != 0 })
    }

    @Test("a weak signal is noise at a low level, a strong one a clean full tone")
    func noise() throws {
        let weak = try Self.heard(.s0).1.map { abs(Int($0)) }.max() ?? 0
        #expect((500...2600).contains(weak))
        let strong = try Self.heard(.s9).1
        #expect((7200...8800).contains(strong.map { abs(Int($0)) }.max() ?? 0))
        let crossings = zip(strong, strong.dropFirst()).filter { $0 < 0 && $1 >= 0 }.count
        #expect((990...1000).contains(crossings))
    }

    @Test("the noise is not random between runs, so that tests can repeat")
    func repeatable() throws {
        #expect(try Self.heard(.s3).1 == Self.heard(.s3).1)
    }

    @Test("overload is clipped, which sounds distorted, but stays within the level")
    func overload() {
        let carrier = SimulatedSignal.overload.carrier
        let samples = (0..<KV4P.audioSampleRate).map(carrier.sample)
        #expect(samples.map { abs(Int($0)) }.max() == Int(carrier.amplitude))
        let flat = samples.filter { abs(Int($0)) == Int(carrier.amplitude) }.count
        #expect(flat > KV4P.audioSampleRate / 4)
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
