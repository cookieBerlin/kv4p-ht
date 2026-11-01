import KV4PProtocol
import Testing

@testable import KV4PSimulator

/// FreeDV 2400B (firmware 17 `rxAudio.h`, `txAudio.h`): the modem runs on the device, the host exchanges Codec2
/// frames.
@Suite("Simulator FreeDV")
struct FreeDVTests {
    static let frames: [[UInt8]] = [[1, 2, 3, 4, 5, 6, 7], [8, 9, 10, 11, 12, 13, 14]]

    @Test("a FreeDV signal opens the squelch; its frames arrive every 40 ms instead of RX audio")
    func receive() throws {
        var scenario = Scenario()
        scenario.carrier = Carrier(voiceFrames: Self.frames)
        var simulator = RXAudioTests.listening(scenario, flags: [.rxAudioOpen, .freeDV2400B])
        let output = try events(simulator.advance(to: .ms(200)))
        let (first, second) = (Self.frames[0], Self.frames[1])
        #expect(output.digitalFrames == [first, second, first, second, first])
        #expect(output.audioBlocks.isEmpty)
        #expect(!simulator.deviceState.radio.flags.contains(.squelched))
        #expect(try events(simulator.advance(to: .ms(239))).digitalFrames.isEmpty)
        #expect(try events(simulator.advance(to: .ms(240))).digitalFrames == [Self.frames[1]])
    }

    @Test("an analog signal keeps the FreeDV squelch closed and sends nothing")
    func analogSignal() throws {
        var scenario = Scenario()
        scenario.carrier = Carrier()
        var simulator = RXAudioTests.listening(scenario, flags: [.rxAudioOpen, .freeDV2400B])
        let output = try events(simulator.advance(to: .ms(200)))
        #expect(output.digitalFrames.isEmpty)
        #expect(output.audioBlocks.isEmpty)
        #expect(simulator.deviceState.radio.flags.contains(.squelched))
    }

    @Test("without FreeDV a FreeDV signal is analog audio; without RX_AUDIO_OPEN no frames are sent")
    func notListening() throws {
        var scenario = Scenario()
        scenario.carrier = Carrier(voiceFrames: Self.frames)
        var analog = RXAudioTests.listening(scenario)
        let output = try events(analog.advance(to: .ms(100)))
        #expect(output.digitalFrames.isEmpty)
        #expect(!output.audioBlocks.isEmpty)
        var closed = RXAudioTests.listening(scenario, flags: [.freeDV2400B])
        #expect(try events(closed.advance(to: .ms(100))).digitalFrames.isEmpty)
    }

    @Test("HOST_TX_DIGITAL is recorded in FreeDV TX only, and feeds the TX watchdog")
    func transmit() throws {
        var simulator = RadioSimulator()
        _ = simulator.connect(at: .zero)
        let flags: StateFlags = [.pttRequested, .txAllowed, .rxAudioOpen, .freeDV2400B]
        _ = simulator.receive(FrameEncoder.desiredState(desiredState(sequence: 1, flags: flags)), at: .ms(10))
        _ = simulator.receive(FrameEncoder.txDigital(Self.frames[0]) + FrameEncoder.txDigital([1, 2, 3]), at: .ms(20))
        _ = simulator.receive(FrameEncoder.txAudio([0x22, 0x00, 0x00, 0x00]), at: .ms(30))
        #expect(simulator.transmittedDigitalFrames == 1)
        #expect(simulator.lastTransmittedDigital == Self.frames[0])
        #expect(simulator.transmittedAudioBlocks == 0)
        _ = simulator.receive(FrameEncoder.txDigital(Self.frames[1]), at: .ms(700))
        #expect(try events(simulator.advance(to: .ms(1000))).states.allSatisfy { $0.mode == .tx })
        #expect(simulator.lastTransmittedDigital == Self.frames[1])
    }

    @Test("HOST_TX_DIGITAL is ignored in analog TX")
    func analogTransmit() {
        var simulator = RadioSimulator()
        _ = simulator.connect(at: .zero)
        let flags: StateFlags = [.pttRequested, .txAllowed, .rxAudioOpen]
        _ = simulator.receive(FrameEncoder.desiredState(desiredState(sequence: 1, flags: flags)), at: .ms(10))
        _ = simulator.receive(FrameEncoder.txDigital(Self.frames[0]), at: .ms(20))
        #expect(simulator.transmittedDigitalFrames == 0)
        #expect(simulator.lastTransmittedDigital == nil)
    }
}
