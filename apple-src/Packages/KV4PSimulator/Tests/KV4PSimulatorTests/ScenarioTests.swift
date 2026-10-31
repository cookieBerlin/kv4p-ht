import KV4PProtocol
import Testing

@testable import KV4PSimulator

/// Scenario settings and fault injection (ADR-0014 C).
@Suite("Simulator scenarios")
struct ScenarioTests {
    @Test("firmware version, features and window size come from the scenario")
    func versionFromScenario() throws {
        var scenario = Scenario()
        scenario.firmwareVersion = 16
        scenario.features = [.physicalPTT]
        scenario.windowSize = 512
        var simulator = RadioSimulator(scenario: scenario)
        guard case .hello(let hello) = try #require(try events(simulator.connect(at: .zero)).first) else {
            Issue.record("no HELLO")
            return
        }
        #expect(hello.version.version == 16)
        #expect(hello.version.features == [.physicalPTT])
        #expect(hello.version.windowSize == 512)
    }

    @Test("without a radio module the configuration is not applied at boot")
    func noRadioModuleAtBoot() throws {
        var simulator = RadioSimulator(scenario: .noRadioModule)
        guard case .hello(let hello) = try #require(try events(simulator.connect(at: .zero)).first) else {
            Issue.record("no HELLO")
            return
        }
        #expect(hello.version.radioModuleStatus == .notFound)
        #expect(hello.deviceState.radioModuleStatus == .notFound)
        #expect(hello.deviceState.radio.freqRx == 0)
        #expect(!hello.deviceState.radio.flags.isEmpty)
    }

    /// The firmware retries SA818 commands forever (`while (!sa818.filters(...))`).
    @Test("without a radio module the first desired state stalls the device")
    func noRadioModuleStalls() throws {
        var simulator = RadioSimulator(scenario: .noRadioModule)
        _ = simulator.connect(at: .zero)
        #expect(!simulator.isStalled)
        #expect(simulator.receive(FrameEncoder.desiredState(desiredState(sequence: 1)), at: .ms(10)).isEmpty)
        #expect(simulator.isStalled)
        #expect(simulator.advance(to: .seconds(5)).isEmpty)
        #expect(simulator.connect(at: .seconds(6)).isEmpty)
        #expect(simulator.hear([0x41], at: .seconds(7)).isEmpty)
        #expect(simulator.disconnect(at: .seconds(8)).isEmpty)
    }

    @Test("a module that stops responding stalls on the next radio command only")
    func moduleStopsResponding() throws {
        var scenario = Scenario()
        scenario.faults.radioModuleStopsResponding = true
        var simulator = RadioSimulator(scenario: scenario)
        let sessionOnly = FrameEncoder.desiredState(RadioState(sequence: 0, flags: [.enableStatusReports]))
        #expect(try events(simulator.receive(sessionOnly, at: .ms(10))).states.count == 1)
        #expect(!simulator.isStalled)
        _ = simulator.receive(FrameEncoder.desiredState(desiredState(sequence: 1)), at: .ms(20))
        #expect(simulator.isStalled)
    }

    @Test("dropped window updates")
    func dropsWindowUpdates() throws {
        var scenario = Scenario()
        scenario.faults.dropsWindowUpdates = true
        var simulator = RadioSimulator(scenario: scenario)
        let output = try events(simulator.receive(FrameEncoder.desiredState(desiredState(sequence: 1)), at: .ms(10)))
        #expect(output.windowUpdates.isEmpty)
        #expect(output.states.count == 1)
    }

    @Test("a device that sends no HELLO")
    func omitsHello() {
        var scenario = Scenario()
        scenario.faults.omitsHello = true
        var simulator = RadioSimulator(scenario: scenario)
        #expect(simulator.connect(at: .zero).isEmpty)
    }

    @Test("garbage before HELLO is ignored by the host parser")
    func garbageBeforeHello() throws {
        var scenario = Scenario()
        scenario.faults.garbageBeforeHello = [0x01, 0xC0, 0xDB, 0x02, 0xC0, 0x00]
        var simulator = RadioSimulator(scenario: scenario)
        let bytes = simulator.connect(at: .zero)
        #expect(bytes.starts(with: scenario.faults.garbageBeforeHello))
        #expect(try events(bytes).count == 1)
    }

    @Test("a raw injection reaches a connected host unchanged")
    func rawInjection() {
        var simulator = RadioSimulator()
        #expect(simulator.inject([0xC0, 0xDB, 0x01], at: .ms(10)).isEmpty)
        _ = simulator.connect(at: .ms(20))
        #expect(simulator.inject([0xC0, 0xDB, 0x01], at: .ms(30)) == [0xC0, 0xDB, 0x01])
    }
}
