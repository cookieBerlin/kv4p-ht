import KV4PProtocol
import Testing

@testable import KV4PSimulator

/// PTT, TX watchdog and runaway TX protection (firmware 17 `txAudio.h`).
@Suite("Simulator transmit")
struct TransmitTests {
    static let audioBlock = FrameEncoder.txAudio([UInt8](repeating: 0x11, count: 128))

    /// A simulator transmitting since 10 ms.
    func transmitting() -> RadioSimulator {
        var simulator = RadioSimulator()
        _ = simulator.connect(at: .zero)
        _ = simulator.receive(
            FrameEncoder.desiredState(desiredState(sequence: 1, flags: [.pttRequested, .txAllowed, .rxAudioOpen])),
            at: .ms(10)
        )
        return simulator
    }

    @Test("PTT with TX_ALLOWED starts transmitting")
    func pttStartsTX() {
        let state = transmitting().deviceState
        #expect(state.mode == .tx)
        #expect(state.radio.flags.isSuperset(of: [.pttRequested, .txActive]))
    }

    @Test("PTT without TX_ALLOWED does not transmit")
    func pttWithoutTXAllowed() {
        var simulator = RadioSimulator()
        _ = simulator.receive(FrameEncoder.desiredState(desiredState(sequence: 1, flags: [.pttRequested])), at: .ms(10))
        #expect(simulator.deviceState.mode == .stopped)
    }

    @Test("clearing PTT returns to RX")
    func pttReleased() {
        var simulator = transmitting()
        let released = desiredState(sequence: 2, flags: [.txAllowed, .rxAudioOpen])
        _ = simulator.receive(FrameEncoder.desiredState(released), at: .ms(100))
        #expect(simulator.deviceState.mode == .rx)
    }

    @Test("without TX audio the watchdog releases PTT after 778 ms")
    func watchdogReleasesPTT() throws {
        var simulator = transmitting()
        #expect(try events(simulator.advance(to: .ms(787))).states.allSatisfy { $0.mode == .tx })
        let state = try #require(try events(simulator.advance(to: .ms(788))).states.last)
        #expect(state.mode == .rx)
        #expect(state.radio.sequence == 2)
        #expect(!state.radio.flags.contains(.pttRequested))
        #expect(!state.radio.flags.contains(.txActive))
    }

    @Test("TX audio keeps the watchdog from firing")
    func audioFeedsWatchdog() {
        var simulator = transmitting()
        for time in stride(from: 500, through: 5000, by: 500) {
            _ = simulator.receive(Self.audioBlock, at: .ms(time))
        }
        _ = simulator.advance(to: .ms(5777))
        #expect(simulator.deviceState.mode == .tx)
        _ = simulator.advance(to: .ms(5778))
        #expect(simulator.deviceState.mode == .rx)
    }

    @Test("runaway TX is stopped after 200 s even with audio")
    func runawayTX() {
        var simulator = transmitting()
        for time in stride(from: 500, through: 200_000, by: 500) {
            _ = simulator.receive(Self.audioBlock, at: .ms(time))
        }
        _ = simulator.advance(to: .ms(200_010))
        #expect(simulator.deviceState.mode == .tx)
        _ = simulator.advance(to: .ms(200_011))
        #expect(simulator.deviceState.mode == .rx)
        #expect(simulator.deviceState.radio.sequence == 2)
    }

    @Test("PTT survives a disconnect until the watchdog fires")
    func disconnectKeepsPTT() {
        var simulator = transmitting()
        _ = simulator.disconnect(at: .ms(100))
        #expect(simulator.deviceState.mode == .tx)
        _ = simulator.advance(to: .seconds(1))
        #expect(simulator.deviceState.mode == .stopped)
    }
}
