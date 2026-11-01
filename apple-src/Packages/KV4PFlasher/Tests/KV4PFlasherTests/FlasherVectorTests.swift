import KV4PProtocol
import KV4PTestSupport
import KV4PTransport
import Synchronization
import Testing

@testable import KV4PFlasher

/// One step of a flash: what the app does to the port, what the device answers, and the progress it reports.
enum FlashStep: Decodable, Equatable, Sendable {
    case baud(Int)
    case lines(dtr: Bool, rts: Bool)
    case write([UInt8])
    case reply([UInt8])
    case connected
    case progress(Int)
    case done(success: Bool)

    private enum Keys: String, CodingKey {
        case event, value, dtr, rts, bytes, success
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        switch try container.decode(String.self, forKey: .event) {
        case "baud": self = .baud(try container.decode(Int.self, forKey: .value))
        case "lines":
            self = .lines(
                dtr: try container.decode(Bool.self, forKey: .dtr),
                rts: try container.decode(Bool.self, forKey: .rts)
            )
        case "write": self = .write(try [UInt8](hex: container.decode(String.self, forKey: .bytes)))
        case "reply": self = .reply(try [UInt8](hex: container.decode(String.self, forKey: .bytes)))
        case "connected": self = .connected
        case "progress": self = .progress(try container.decode(Int.self, forKey: .value))
        default: self = .done(success: try container.decode(Bool.self, forKey: .success))
        }
    }
}

/// Replays a recorded device: after the n-th write it answers what the recording answered (or `replies[n]`), and
/// logs every step in order.
final class TranscriptPort: BootloaderPort {
    /// The operation that fails with `.ioFailed(errno: 5)`.
    enum Failure: CaseIterable, Sendable {
        case baud, lines, write, read
    }

    private struct State {
        var log: [FlashStep] = []
        var pending: [UInt8] = []
        var writes = 0
    }

    private let replies: [Int: [UInt8]]
    private let clock: VirtualClock
    private let state = Mutex(State())
    private let failure: Failure?

    /// `replies[n]`: what the device answers to the n-th write; writes without an entry stay unanswered.
    init(
        transcript: [FlashStep],
        replacing overrides: [Int: [UInt8]] = [:],
        clock: VirtualClock,
        failure: Failure? = nil
    ) {
        var replies: [Int: [UInt8]] = [:]
        var writes = -1
        for step in transcript {
            switch step {
            case .write: writes += 1
            case .reply(let bytes): replies[writes] = bytes
            default: break
            }
        }
        self.replies = replies.merging(overrides) { $1 }
        self.clock = clock
        self.failure = failure
    }

    var log: [FlashStep] { state.withLock { $0.log } }

    func record(_ step: FlashStep) {
        state.withLock { $0.log.append(step) }
    }

    private func fail(_ operation: Failure) throws(TransportError) {
        if failure == operation { throw .ioFailed(errno: 5) }
    }

    func setBaudRate(_ rate: Int) throws(TransportError) {
        try fail(.baud)
        record(.baud(rate))
    }

    func setModemLines(dtr: Bool, rts: Bool) throws(TransportError) {
        try fail(.lines)
        record(.lines(dtr: dtr, rts: rts))
    }

    func write(_ bytes: [UInt8]) throws(TransportError) {
        try fail(.write)
        state.withLock { state in
            state.log.append(.write(bytes))
            if let reply = replies[state.writes], !reply.isEmpty {
                state.log.append(.reply(reply))
                state.pending += reply
            }
            state.writes += 1
        }
    }

    func read(timeout: Duration) async throws(TransportError) -> [UInt8] {
        try fail(.read)
        let bytes = state.withLock { state in
            defer { state.pending = [] }
            return state.pending
        }
        if bytes.isEmpty {
            try? await clock.sleep(for: timeout)
        }
        return bytes
    }
}

@Suite("Flasher vectors")
struct FlasherVectorTests {
    struct Input: Decodable, Sendable {
        let bootloader: String
        let partitions: String
        let bootApp0: String
        let app: String

        var images: FirmwareImages {
            get throws {
                FirmwareImages(
                    bootloader: try [UInt8](hex: bootloader),
                    partitions: try [UInt8](hex: partitions),
                    bootApp0: try [UInt8](hex: bootApp0),
                    app: try [UInt8](hex: app)
                )
            }
        }
    }

    struct Expected: Decodable, Sendable {
        let transcript: [FlashStep]
    }

    struct Packaged: Decodable, Sendable {
        let version: UInt16
    }

    static let vectors = (try? VectorFile<Input, Expected>.load("flasher", from: .module)) ?? []
    static let packaged = (try? VectorFile<[String: String], Packaged>.load("packaged-firmware", from: .module)) ?? []

    static func vector(_ name: String) throws -> VectorFile<Input, Expected>.Vector {
        try #require(vectors.first { $0.name == name })
    }

    /// Flashes the vector's images into `port`; returns the error, if any, after logging the result.
    @discardableResult
    static func flash(_ vector: VectorFile<Input, Expected>.Vector, into port: TranscriptPort, clock: VirtualClock)
        async throws -> FlashError?
    {
        let flasher = ESP32Flasher(port: port, clock: clock, stub: try FlasherStub.esp32())
        let images = try vector.input.images
        do throws(FlashError) {
            try await flasher.flash(images) { event in
                switch event {
                case .connected: port.record(.connected)
                case .progress(let percent): port.record(.progress(percent))
                }
            }
            port.record(.done(success: true))
            return nil
        } catch {
            port.record(.done(success: false))
            return error
        }
    }

    @Test("vector files are present")
    func vectorsPresent() {
        #expect(Self.vectors.map(\.name) == ["flash", "wrong md5", "no answer"])
        #expect(Self.packaged.count == 1)
    }

    @Test("flashes like Android, step by step", arguments: vectors)
    func replay(vector: VectorFile<Input, Expected>.Vector) async throws {
        let clock = VirtualClock()
        let port = TranscriptPort(transcript: vector.expected.transcript, clock: clock)
        let error = try await Self.flash(vector, into: port, clock: clock)
        let log = port.log
        let expected = vector.expected.transcript
        let difference = log.indices.first { $0 >= expected.count || log[$0] != expected[$0] } ?? log.count
        #expect(log == vector.expected.transcript, "first difference at step \(difference) of \(log.count)")
        switch vector.name {
        case "flash": #expect(error == nil)
        case "wrong md5": #expect(error == .verifyFailed(offset: 0x1000))
        default: #expect(error == .noAnswer)
        }
    }

    @Test("the app accepts the firmware version Android packages")
    func packagedVersion() throws {
        #expect(KV4P.packagedFirmwareVersion == (try #require(Self.packaged.first)).expected.version)
    }
}
