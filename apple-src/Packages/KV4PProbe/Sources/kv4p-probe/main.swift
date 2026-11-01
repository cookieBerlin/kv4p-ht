// Development tool for the hardware checklist: connects to a kv4p HT and prints its HELLO.
// Entry point only, excluded from coverage (ADR-0011).
#if os(macOS)
    import Foundation
    import KV4PAPRS
    import KV4PAudio
    import KV4PProtocol
    import KV4PRadio
    import KV4PTransport

    let usage = """
        usage: kv4p-probe [--ble [<peripheral UUID>]] [--verbose] [--tune <MHz> | --listen <seconds>]
               kv4p-probe --serial [<device>] [--reset] [--verbose] [--tune <MHz> | --listen <seconds>]
               kv4p-probe --list
        Connects, waits up to 10 s for HELLO and prints it.
        With --tune <MHz>, the RadioController handshakes, tunes RX and TX and waits until the radio confirms.
        With --listen <seconds>, it receives RX audio and prints the block rate and the largest gap, and every APRS
        packet; with --tune as well, it tunes first.
        """

    /// Records when `RX_AUDIO` blocks arrive (`--listen`).
    final class ArrivalLog: RXAudioSink, @unchecked Sendable {
        private let lock = NSLock()
        private var arrivals: [ContinuousClock.Instant] = []
        private var samples = 0
        private var peak: Int16 = 0

        func receive(block: [UInt8]) {
            let decoded = ImaAdpcm.decodeBlock(block, maxSamples: KV4P.audioBlockSamples)
            lock.withLock {
                arrivals.append(.now)
                samples += decoded.count
                peak = max(peak, decoded.map { $0 == .min ? .max : abs($0) }.max() ?? 0)
            }
        }

        func reset() {}

        var summary: String {
            lock.withLock {
                guard let first = arrivals.first, let last = arrivals.last, arrivals.count > 1 else {
                    return "\(arrivals.count) RX audio blocks"
                }
                let gaps = zip(arrivals, arrivals.dropFirst()).map { $0.duration(to: $1) }
                // Samples after the first arrival, over the time since then.
                let rate = Double(samples - KV4P.audioBlockSamples) / (first.duration(to: last) / .seconds(1))
                return "\(arrivals.count) RX audio blocks, \(Int(rate)) samples/s, "
                    + "largest gap \(gaps.max() ?? .zero), peak \(peak)\n"
                    + [2, 4, 6, 8].map { replay(prefillBlocks: $0) }.joined(separator: "\n")
            }
        }

        /// Replays the arrivals into a `JitterBuffer` that plays at exactly 16 kHz in 10 ms periods.
        private func replay(prefillBlocks: Int) -> String {
            var buffer = JitterBuffer(prefill: prefillBlocks * KV4P.audioBlockSamples)
            let period = Duration.milliseconds(10)
            let chunk = KV4P.audioSampleRate / 100
            var output = [Int16](repeating: 0, count: chunk)
            var next = arrivals[0]
            for arrival in arrivals {
                while next < arrival {
                    output.withUnsafeMutableBufferPointer { buffer.pull(into: $0) }
                    next = next.advanced(by: period)
                }
                buffer.push(repeatElement(Int16(0), count: KV4P.audioBlockSamples))
            }
            return "  prefill \(prefillBlocks) blocks: \(buffer.underruns) underruns, "
                + "\(buffer.droppedSamples) samples dropped"
        }
    }

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
    @MainActor func option(_ name: String) -> Float? {
        guard let index = arguments.firstIndex(of: name) else { return nil }
        guard index + 1 < arguments.count, let value = Float(arguments[index + 1]) else { fail(usage) }
        arguments.removeSubrange(index...index + 1)
        return value
    }
    let tune = option("--tune")
    let listen = option("--listen")
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

    let helloDeadline = Task {
        try? await Task.sleep(for: .seconds(10))
        if !Task.isCancelled { fail("no HELLO within 10 s") }
    }

    if let listen {
        let log = ArrivalLog()
        let controller = RadioController(transport: transport, rxAudio: log)
        var snapshots = controller.snapshots.makeAsyncIterator()
        await controller.connect()
        while let snapshot = await snapshots.next() {
            if case .failed(let failure) = snapshot.status { fail("failed: \(failure)") }
            if snapshot.status == .ready { break }
        }
        helloDeadline.cancel()
        if let tune {
            do {
                try await controller.tune(rx: tune, tx: tune)
            } catch {
                fail("tune failed: \(error)")
            }
        }
        let frames = controller.receivedFrames
        Task {
            var feed = APRSEventLog()
            for await frame in frames {
                guard let packet = try? APRSParser.parse(ax25: frame) else {
                    print("  frame   \(frame.count) bytes, not APRS")
                    continue
                }
                let event = feed.receive(packet, atMs: RadioViewModel.systemTimeMs())
                let path = packet.digipeaters.map(\.description).joined(separator: ",")
                print(
                    "  APRS    \(packet.source)>\(packet.destination)\(path.isEmpty ? "" : "," + path)",
                    terminator: ""
                )
                print(event.map { " → \($0.kind) \($0.comment ?? $0.body ?? "")" } ?? " (no event)")
            }
        }
        print("listening for \(listen) s")
        try? await Task.sleep(for: .seconds(Double(listen)))
        let squelched = await controller.snapshot.deviceState?.radio.flags.contains(.squelched) ?? true
        print(log.summary + (squelched ? ", squelch closed" : ", squelch open"))
        await controller.disconnect()
        exit(0)
    }

    if let tune, listen == nil {
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
