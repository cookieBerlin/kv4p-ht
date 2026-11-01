import KV4PProtocol
import Testing

/// What the host sees: the simulator output read with the host-side `KISSParser`, as the app does.
enum Event: Equatable {
    case hello(Hello)
    case state(DeviceState)
    case window(UInt32)
    case ax25([UInt8])
    case audio([UInt8])
}

func events(_ bytes: [UInt8]) throws -> [Event] {
    var parser = KISSParser()
    return try parser.process(bytes).map { frame in
        switch frame {
        case .ax25(let packet): .ax25(packet)
        case .command(.hello, let payload): .hello(try Hello(decoding: payload))
        case .command(.deviceState, let payload): .state(try DeviceState(decoding: payload))
        case .command(.windowUpdate, let payload): .window(try WindowUpdate(decoding: payload).size)
        case .command(.rxAudio, let payload): .audio(payload)
        case .command(let command, _): throw UnexpectedCommand(command: command)
        }
    }
}

struct UnexpectedCommand: Error {
    let command: DeviceCommand
}

extension [Event] {
    var states: [DeviceState] {
        compactMap { if case .state(let state) = $0 { state } else { nil } }
    }

    var audioBlocks: [[UInt8]] {
        compactMap { if case .audio(let block) = $0 { block } else { nil } }
    }

    var windowUpdates: [UInt32] {
        compactMap { if case .window(let size) = $0 { size } else { nil } }
    }
}

extension Duration {
    static func ms(_ value: Int) -> Duration { .milliseconds(value) }
}

/// A configured VHF simplex channel with status reports, as the app sends after HELLO.
func desiredState(
    sequence: UInt32,
    flags: StateFlags = [],
    freq: Float = 146.52
) -> RadioState {
    RadioState(
        sequence: sequence,
        memoryId: 3,
        flags: flags.union([.radioConfigValid, .enableStatusReports]),
        bandwidth: 1,
        freqTx: freq,
        freqRx: freq,
        squelch: 1
    )
}
