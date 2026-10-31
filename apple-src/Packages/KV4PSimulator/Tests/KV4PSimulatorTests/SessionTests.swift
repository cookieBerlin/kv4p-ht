import KV4PProtocol
import Testing

@testable import KV4PSimulator

/// HELLO, desired-state handling, status reports and window updates (firmware 17).
@Suite("Simulator session")
struct SessionTests {
    @Test("HELLO describes a new VHF device")
    func helloNewDevice() throws {
        var simulator = RadioSimulator()
        let hello = try #require(try events(simulator.connect(at: .zero)).first)
        let expected = Hello(
            version: FirmwareVersion(
                version: 17,
                radioModuleStatus: .found,
                windowSize: 2048,
                moduleType: .sa818VHF,
                minRadioFreq: 134,
                maxRadioFreq: 174,
                features: [.highLowPower, .esp32AFSK]
            ),
            deviceState: DeviceState(
                radio: RadioState(
                    sequence: 0,
                    memoryId: -1,
                    flags: [.radioConfigValid, .highPower, .rssiEnabled, .squelched],
                    bandwidth: 1,
                    freqTx: 144,
                    freqRx: 144
                ),
                radioModuleStatus: .found,
                mode: .stopped
            )
        )
        #expect(hello == .hello(expected))
    }

    @Test("a UHF module reports its limits and default frequency")
    func helloUHF() throws {
        var simulator = RadioSimulator(scenario: .uhf)
        guard case .hello(let hello) = try #require(try events(simulator.connect(at: .zero)).first) else {
            Issue.record("no HELLO")
            return
        }
        #expect(hello.version.moduleType == .sa818UHF)
        #expect([hello.version.minRadioFreq, hello.version.maxRadioFreq] == [400, 480])
        #expect(hello.deviceState.radio.freqRx == 435)
    }

    @Test("BLE sessions advertise a 4096-byte window")
    func bleWindow() throws {
        var simulator = RadioSimulator(scenario: .ble)
        guard case .hello(let hello) = try #require(try events(simulator.connect(at: .zero)).first) else {
            Issue.record("no HELLO")
            return
        }
        #expect(hello.version.windowSize == 4096)
    }

    @Test("the stored state is loaded like the firmware does at boot")
    func storedState() {
        var scenario = Scenario()
        scenario.storedState = RadioState(
            sequence: 9,
            memoryId: 4,
            flags: [.pttRequested, .rxAudioOpen, .txAllowed, .squelched],
            bandwidth: 0,
            freqTx: 100,
            freqRx: 145.5,
            ctcssTx: 2,
            squelch: 3,
            ctcssRx: 4
        )
        let radio = RadioSimulator(scenario: scenario).deviceState.radio
        #expect(radio.sequence == 0)
        #expect(radio.memoryId == -1)
        #expect(radio.flags == [.radioConfigValid, .txAllowed, .squelched])
        #expect([radio.freqTx, radio.freqRx] == [134, 145.5])
        #expect([radio.bandwidth, radio.ctcssTx, radio.squelch, radio.ctcssRx] == [0, 2, 3, 4])
    }

    @Test("a new desired state is acknowledged, applied and reported")
    func desiredStateApplied() throws {
        var simulator = RadioSimulator()
        _ = simulator.connect(at: .zero)
        let frame = FrameEncoder.desiredState(desiredState(sequence: 1, flags: [.rxAudioOpen]))
        let output = try events(simulator.receive(frame, at: .ms(10)))
        #expect(output.count == 2)
        #expect(output.first == .window(UInt32(frame.count)))
        let state = try #require(output.states.first)
        #expect(state.radio.sequence == 1)
        #expect(state.radio.memoryId == 3)
        #expect(state.radio.freqRx == 146.52)
        #expect(state.radio.squelch == 1)
        #expect(state.mode == .rx)
        #expect(state.radio.flags.isSuperset(of: [.radioConfigValid, .rxAudioOpen, .enableStatusReports]))
    }

    @Test("each frame of a chunk is acknowledged before its report")
    func chunkOrder() throws {
        var simulator = RadioSimulator()
        _ = simulator.connect(at: .zero)
        let first = FrameEncoder.desiredState(desiredState(sequence: 1))
        let second = FrameEncoder.desiredState(desiredState(sequence: 2, freq: 145.5))
        let output = try events(simulator.receive(first + second, at: .ms(10)))
        #expect(output.windowUpdates == [UInt32(first.count), UInt32(second.count)])
        #expect(output.states.map(\.radio.sequence) == [1, 2])
        #expect(output.map { if case .window = $0 { "w" } else { "s" } } == ["w", "s", "w", "s"])
    }

    @Test("a stale sequence keeps the global state but still applies session flags")
    func staleSequence() throws {
        var simulator = RadioSimulator()
        _ = simulator.connect(at: .zero)
        _ = simulator.receive(FrameEncoder.desiredState(desiredState(sequence: 5)), at: .ms(10))
        let stale = desiredState(sequence: 5, flags: [.rxAudioOpen], freq: 145.5)
        let state = try #require(try events(simulator.receive(FrameEncoder.desiredState(stale), at: .ms(20))).states.last)
        #expect(state.radio.freqRx == 146.52)
        #expect(state.radio.flags.contains(.rxAudioOpen))
        #expect(state.mode == .rx)
    }

    @Test("device-only flags sent by the host are ignored")
    func deviceOnlyFlags() {
        var simulator = RadioSimulator()
        let flags: StateFlags = [.physicalPTTDown, .txActive, .freeDV2400B]
        _ = simulator.receive(FrameEncoder.desiredState(desiredState(sequence: 1, flags: flags)), at: .ms(10))
        #expect(simulator.deviceState.radio.flags.intersection([.physicalPTTDown, .txActive]).isEmpty)
        #expect(simulator.deviceState.radio.flags.contains(.freeDV2400B))
    }

    @Test("a desired state with a wrong length is acknowledged but ignored")
    func wrongLength() throws {
        var simulator = RadioSimulator()
        let frame = FrameEncoder.vendor(.desiredState, desiredState(sequence: 1).encoded().dropLast())
        #expect(try events(simulator.receive(frame, at: .ms(10))) == [.window(UInt32(frame.count))])
        #expect(simulator.deviceState.radio.sequence == 0)
    }

    @Test("frames the firmware ignores are acknowledged")
    func ignoredFrames() throws {
        var simulator = RadioSimulator()
        let frames: [[UInt8]] = [[0xC0, 0x10, 0x41, 0xC0], FrameEncoder.txDigital([1, 2, 3, 4, 5, 6, 7])]
        for frame in frames {
            #expect(try events(simulator.receive(frame, at: .ms(10))) == [.window(UInt32(frame.count))])
        }
    }

    @Test("without ENABLE_STATUS_REPORTS only window updates are sent")
    func noReports() throws {
        var simulator = RadioSimulator()
        var state = desiredState(sequence: 1)
        state.flags.remove(.enableStatusReports)
        let frame = FrameEncoder.desiredState(state)
        #expect(try events(simulator.receive(frame, at: .ms(10))) == [.window(UInt32(frame.count))])
        #expect(try events(simulator.advance(to: .seconds(3))).isEmpty)
    }

    @Test("status reports are sent every 500 ms")
    func periodicReports() throws {
        var simulator = RadioSimulator()
        _ = simulator.receive(FrameEncoder.desiredState(desiredState(sequence: 1)), at: .ms(10))
        #expect(try events(simulator.advance(to: .ms(499))).isEmpty)
        #expect(try events(simulator.advance(to: .ms(500))).states.count == 1)
        #expect(try events(simulator.advance(to: .ms(2500))).states.count == 4)
        #expect(simulator.now == .ms(2500))
    }

    @Test("advancing to the current time sends nothing new")
    func advanceToNow() throws {
        var simulator = RadioSimulator()
        _ = simulator.receive(FrameEncoder.desiredState(desiredState(sequence: 1)), at: .ms(500))
        #expect(try events(simulator.advance(to: .ms(500))).isEmpty)
    }

    @Test("disconnecting clears the session flags and a reconnect sends HELLO again")
    func reconnect() throws {
        var simulator = RadioSimulator()
        _ = simulator.connect(at: .zero)
        _ = simulator.receive(FrameEncoder.desiredState(desiredState(sequence: 1, flags: [.rxAudioOpen])), at: .ms(10))
        #expect(try events(simulator.disconnect(at: .ms(20))).isEmpty)
        #expect(simulator.deviceState.mode == .stopped)
        #expect(simulator.deviceState.radio.flags.isDisjoint(with: StateFlags.sessionScope))
        #expect(try events(simulator.advance(to: .seconds(2))).isEmpty)
        guard case .hello(let hello) = try #require(try events(simulator.connect(at: .seconds(3))).first) else {
            Issue.record("no HELLO")
            return
        }
        #expect(hello.deviceState.radio.sequence == 1)
        #expect(hello.deviceState.radio.freqRx == 146.52)
    }

    @Test("a frame split across reads is parsed once complete")
    func splitFrame() throws {
        var simulator = RadioSimulator()
        let frame = FrameEncoder.desiredState(desiredState(sequence: 1))
        #expect(try events(simulator.receive(frame.prefix(10), at: .ms(10))).isEmpty)
        #expect(try events(simulator.receive(frame.dropFirst(10), at: .ms(11))).windowUpdates == [UInt32(frame.count)])
    }

    @Test("a disconnect drops a partially received frame")
    func disconnectResetsParser() throws {
        var simulator = RadioSimulator()
        let frame = FrameEncoder.desiredState(desiredState(sequence: 1))
        _ = simulator.receive(frame.prefix(10), at: .ms(10))
        _ = simulator.disconnect(at: .ms(20))
        _ = simulator.connect(at: .ms(30))
        #expect(try events(simulator.receive(frame.dropFirst(10), at: .ms(40))).isEmpty)
    }
}
