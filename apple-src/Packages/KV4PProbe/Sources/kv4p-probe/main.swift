// Development tool for the hardware checklist: connects to a kv4p HT and prints its HELLO.
// Entry point only, excluded from coverage (ADR-0011).
#if os(macOS)
    import Foundation
    import KV4PProtocol
    import KV4PRadio
    import KV4PTransport

    let usage = """
        usage: kv4p-probe [--ble [<peripheral UUID>]] [--verbose]
               kv4p-probe --serial [<device>] [--reset] [--verbose]
               kv4p-probe --list
        Connects, waits up to 10 s for HELLO and prints it.
        With --tune <MHz>, the RadioController handshakes, tunes RX and TX and waits until the radio confirms.
        """

    /// Prints every BLE event and command (`--verbose`), to see where the connection sequence stops.
    final class LoggingCentral: BLECentral {
        let events: AsyncStream<BLEEvent>
        private let central: any BLECentral

        init(_ central: any BLECentral) {
            self.central = central
            let (events, continuation) = AsyncStream.makeStream(of: BLEEvent.self)
            self.events = events
            Task {
                for await event in central.events {
                    print("  event   \(event)")
                    continuation.yield(event)
                }
            }
        }

        func perform(_ command: BLECommand) {
            print("  command \(command)")
            central.perform(command)
        }
    }

    func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }

    // Line-buffered, so the output can be piped into a log.
    setvbuf(stdout, nil, _IOLBF, 0)

    var arguments = Array(CommandLine.arguments.dropFirst())
    var tune: Float?
    if let index = arguments.firstIndex(of: "--tune") {
        guard index + 1 < arguments.count, let frequency = Float(arguments[index + 1]) else { fail(usage) }
        tune = frequency
        arguments.removeSubrange(index...index + 1)
    }
    let operand = arguments.dropFirst().first { !$0.hasPrefix("--") }
    let transport: any RadioTransport
    switch arguments.first {
    case "--list":
        print(POSIXSerialPort.devices().joined(separator: "\n"))
        exit(0)
    case "--serial":
        guard let path = operand ?? POSIXSerialPort.devices().first else { fail("no USB serial device found") }
        print("serial \(path)")
        transport = SerialTransport(port: POSIXSerialPort(path: path), resetOnConnect: arguments.contains("--reset"))
    case "--ble", nil:
        print("BLE")
        let central: any BLECentral = CoreBluetoothCentral()
        transport = BLETransport(
            central: arguments.contains("--verbose") ? LoggingCentral(central) : central,
            peripheral: operand.flatMap(UUID.init(uuidString:))
        )
    default:
        fail(usage)
    }

    Task {
        try? await Task.sleep(for: .seconds(10))
        fail("no HELLO within 10 s")
    }

    if let tune {
        let controller = RadioController(transport: transport)
        var snapshots = controller.snapshots.makeAsyncIterator()
        var tuning = false
        await controller.connect()
        while let snapshot = await snapshots.next() {
            let rx = snapshot.deviceState?.radio.freqRx ?? 0
            print(
                "  \(snapshot.status), in sync \(snapshot.isInSync), sequence \(snapshot.desired.sequence), RX \(rx) MHz"
            )
            if case .failed(let failure) = snapshot.status { fail("failed: \(failure)") }
            guard snapshot.status == .ready, snapshot.isInSync else { continue }
            if rx == tune {
                print("tuned to \(tune) MHz and confirmed by the radio")
                await controller.disconnect()
                exit(0)
            }
            if !tuning {
                tuning = true
                do {
                    try await controller.tune(rx: tune, tx: tune)
                } catch {
                    fail("tune failed: \(error)")
                }
            }
        }
        fail("controller stopped")
    }

    print("connecting…")
    do {
        try await transport.connect()
    } catch {
        fail("connection failed: \(error)")
    }
    print("connected, waiting for HELLO")

    var parser = KISSParser()
    let verbose = arguments.contains("--verbose")
    for await chunk in transport.incoming {
        if verbose {
            // Text outside KISS frames, e.g. the boot log on USB.
            let text = String(decoding: chunk.filter { (0x20..<0x7F).contains($0) || $0 == 0x0A }, as: UTF8.self)
            if !text.isEmpty { print("  raw     \(text)") }
        }
        for frame in parser.process(chunk) {
            guard case .command(.hello, let payload) = frame else {
                print("frame: \(frame)")
                continue
            }
            do {
                let hello = try Hello(decoding: payload)
                let version = hello.version
                let state = hello.deviceState
                print("firmware \(version.version), module \(version.moduleType), status \(version.radioModuleStatus)")
                print("range \(version.minRadioFreq)–\(version.maxRadioFreq) MHz, window \(version.windowSize) bytes")
                print("features \(String(version.features.rawValue, radix: 2))")
                print("state: sequence \(state.radio.sequence), mode \(state.mode), RX \(state.radio.freqRx) MHz")
                print("TX \(state.radio.freqTx) MHz, flags 0x\(String(state.radio.flags.rawValue, radix: 16))")
                await transport.disconnect()
                exit(0)
            } catch {
                fail("invalid HELLO: \(error)")
            }
        }
    }
    fail("connection closed")
#endif
