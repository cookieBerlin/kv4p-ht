// Simulated kv4p HT over real BLE (ADR-0014 B): advertises the KV4P GATT service and serves RadioSimulator.
// Run it on one Mac and connect from another device (a Mac cannot discover its own advertisement).
// Entry point only, excluded from coverage (ADR-0011).
#if os(macOS)
    import Foundation
    import KV4PSimulator

    let usage = """
        usage: kv4p-sim-peripheral [--uhf] [--no-radio-module] [--verbose]
        Advertises as kv4p-sim until stopped with Ctrl-C.
        """

    /// Prints every event and command (`--verbose`); notifications and writes as byte counts.
    final class LoggingPeripheralManager: BLEPeripheralManager {
        let events: AsyncStream<PeripheralEvent>
        private let manager: any BLEPeripheralManager

        init(_ manager: any BLEPeripheralManager) {
            self.manager = manager
            let (events, continuation) = AsyncStream.makeStream(of: PeripheralEvent.self)
            self.events = events
            Task {
                for await event in manager.events {
                    if case .write(let bytes) = event {
                        print("  event   write \(bytes.count) bytes")
                    } else {
                        print("  event   \(event)")
                    }
                    continuation.yield(event)
                }
            }
        }

        func perform(_ command: PeripheralCommand) {
            if case .notify(let bytes) = command {
                print("  command notify \(bytes.count) bytes")
            } else {
                print("  command \(command)")
            }
            manager.perform(command)
        }
    }

    // Line-buffered, so the output can be piped into a log.
    setvbuf(stdout, nil, _IOLBF, 0)

    let arguments = Set(CommandLine.arguments.dropFirst())
    guard arguments.isSubset(of: ["--uhf", "--no-radio-module", "--verbose"]) else {
        print(usage)
        exit(1)
    }
    var scenario = Scenario.ble
    if arguments.contains("--uhf") {
        scenario.moduleType = .sa818UHF
    }
    if arguments.contains("--no-radio-module") {
        scenario.radioModuleStatus = .notFound
    }
    let central = CoreBluetoothPeripheralManager()
    let manager: any BLEPeripheralManager =
        arguments.contains("--verbose") ? LoggingPeripheralManager(central) : central
    print("advertising as kv4p-sim (\(scenario.moduleType)), Ctrl-C to stop")
    await SimulatorPeripheral(manager: manager, simulator: RadioSimulator(scenario: scenario)).run()
#endif
