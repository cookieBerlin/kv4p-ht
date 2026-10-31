import KV4PTestSupport
import Testing

@testable import KV4PProtocol

/// Checks the message codecs against the Android `Protocol` decoders and `HostDesiredState.toBytes`.
@Suite("Message vectors")
struct MessageVectorTests {
    struct StateJSON: Decodable, Sendable {
        let sequence: Int64
        let memoryId: Int64
        let flags: Int64
        let bw: Int64
        let freqTx: Float
        let freqRx: Float
        let ctcssTx: Int64
        let squelch: Int64
        let ctcssRx: Int64

        var radioState: RadioState {
            RadioState(
                sequence: UInt32(truncatingIfNeeded: sequence),
                memoryId: Int32(truncatingIfNeeded: memoryId),
                flags: StateFlags(rawValue: UInt16(truncatingIfNeeded: flags)),
                bandwidth: UInt8(truncatingIfNeeded: bw),
                freqTx: freqTx,
                freqRx: freqRx,
                ctcssTx: UInt8(truncatingIfNeeded: ctcssTx),
                squelch: UInt8(truncatingIfNeeded: squelch),
                ctcssRx: UInt8(truncatingIfNeeded: ctcssRx)
            )
        }
    }

    struct Input: Decodable, Sendable {
        let type: String
        let state: StateJSON?
        let bytes: String?
        let len: Int?
    }

    struct DeviceStateJSON: Decodable, Sendable {
        let appliedSequence: Int64
        let memoryId: Int64
        let flags: Int64
        let bw: Int64
        let freqTx: Float
        let freqRx: Float
        let ctcssTx: Int64
        let squelch: Int64
        let ctcssRx: Int64
        let radioModuleStatus: String
        let mode: String
        let lastError: Int64
        let latestRssi: Int64
        let hasRadioConfig: Bool

        func check(_ state: DeviceState) {
            #expect(state.radio.sequence == UInt32(truncatingIfNeeded: appliedSequence))
            #expect(state.radio.memoryId == Int32(truncatingIfNeeded: memoryId))
            #expect(state.radio.flags.rawValue == UInt16(truncatingIfNeeded: flags))
            #expect(state.radio.bandwidth == UInt8(truncatingIfNeeded: bw))
            #expect(state.radio.freqTx == freqTx)
            #expect(state.radio.freqRx == freqRx)
            #expect(state.radio.ctcssTx == UInt8(truncatingIfNeeded: ctcssTx))
            #expect(state.radio.squelch == UInt8(truncatingIfNeeded: squelch))
            #expect(state.radio.ctcssRx == UInt8(truncatingIfNeeded: ctcssRx))
            #expect(androidName(state.radioModuleStatus) == radioModuleStatus)
            #expect(androidName(state.mode) == mode)
            #expect(Int64(state.lastError) == lastError)
            #expect(Int64(state.latestRssi) == latestRssi)
            #expect(state.hasRadioConfig == hasRadioConfig)
        }
    }

    struct VersionJSON: Decodable, Sendable {
        let ver: Int64
        let radioModuleStatus: String
        let windowSize: Int64
        let moduleType: String
        let minRadioFreq: Float
        let maxRadioFreq: Float
        let hasHl: Bool
        let hasPhysPtt: Bool
        let hasFreeDv2400b: Bool

        func check(_ version: FirmwareVersion) {
            #expect(version.version == UInt16(truncatingIfNeeded: ver))
            #expect(androidName(version.radioModuleStatus) == radioModuleStatus)
            #expect(version.windowSize == UInt32(truncatingIfNeeded: windowSize))
            #expect(androidName(version.moduleType) == moduleType)
            #expect(version.minRadioFreq == minRadioFreq)
            #expect(version.maxRadioFreq == maxRadioFreq)
            #expect(version.features.contains(.highLowPower) == hasHl)
            #expect(version.features.contains(.physicalPTT) == hasPhysPtt)
            #expect(version.features.contains(.freeDV2400B) == hasFreeDv2400b)
        }
    }

    struct HelloJSON: Decodable, Sendable {
        let version: VersionJSON
        let deviceState: DeviceStateJSON
    }

    struct WindowJSON: Decodable, Sendable {
        let size: Int64
    }

    /// The decoded value; exactly one member matches, depending on the input type.
    struct ValueJSON: Decodable, Sendable {
        let deviceState: DeviceStateJSON?
        let version: VersionJSON?
        let hello: HelloJSON?
        let window: WindowJSON?

        init(from decoder: any Decoder) throws {
            deviceState = try? DeviceStateJSON(from: decoder)
            version = try? VersionJSON(from: decoder)
            hello = try? HelloJSON(from: decoder)
            window = try? WindowJSON(from: decoder)
        }
    }

    struct Expected: Decodable, Sendable {
        let bytes: String?
        let value: ValueJSON?
        let error: String?
    }

    typealias Vector = VectorFile<Input, Expected>.Vector

    static let vectors = (try? VectorFile<Input, Expected>.load("messages", from: .module)) ?? []

    static func vectors(_ type: String) -> [Vector] { vectors.filter { $0.input.type == type } }

    @Test("vector file covers every message type")
    func vectorsPresent() {
        for type in ["HostDesiredState", "DeviceState", "FirmwareVersion", "Hello", "WindowUpdate"] {
            #expect(!Self.vectors(type).isEmpty, "\(type)")
        }
    }

    @Test("HostDesiredState encodes like Android", arguments: vectors("HostDesiredState"))
    func encodeHostDesiredState(vector: Vector) throws {
        let state = try #require(vector.input.state).radioState
        #expect(state.encoded() == (try [UInt8](hex: try #require(vector.expected.bytes))))
    }

    @Test("HostDesiredState round-trips through the decoder", arguments: vectors("HostDesiredState"))
    func roundTripHostDesiredState(vector: Vector) throws {
        let state = try #require(vector.input.state).radioState
        #expect(try RadioState(decoding: state.encoded()) == state)
    }

    @Test("DeviceState decodes like Android", arguments: vectors("DeviceState"))
    func decodeDeviceState(vector: Vector) throws {
        try check(vector, decode: DeviceState.init(decoding:)) { try #require($0.deviceState).check($1) }
    }

    @Test("FirmwareVersion decodes like Android", arguments: vectors("FirmwareVersion"))
    func decodeFirmwareVersion(vector: Vector) throws {
        try check(vector, decode: FirmwareVersion.init(decoding:)) { try #require($0.version).check($1) }
    }

    @Test("Hello decodes like Android", arguments: vectors("Hello"))
    func decodeHello(vector: Vector) throws {
        try check(vector, decode: Hello.init(decoding:)) { value, hello in
            let expected = try #require(value.hello)
            expected.version.check(hello.version)
            expected.deviceState.check(hello.deviceState)
        }
    }

    @Test("WindowUpdate decodes like Android", arguments: vectors("WindowUpdate"))
    func decodeWindowUpdate(vector: Vector) throws {
        try check(vector, decode: WindowUpdate.init(decoding:)) { value, update in
            let expected = try #require(value.window)
            #expect(update.size == UInt32(truncatingIfNeeded: expected.size))
        }
    }

    @Test("DeviceState re-encodes to the decoded bytes", arguments: vectors("DeviceState"))
    func reencodeDeviceState(vector: Vector) throws {
        try checkReencoding(vector, decode: DeviceState.init(decoding:)) { $0.encoded() }
    }

    @Test("FirmwareVersion re-encodes to the decoded bytes", arguments: vectors("FirmwareVersion"))
    func reencodeFirmwareVersion(vector: Vector) throws {
        try checkReencoding(vector, decode: FirmwareVersion.init(decoding:)) { $0.encoded() }
    }

    @Test("Hello re-encodes to the decoded bytes", arguments: vectors("Hello"))
    func reencodeHello(vector: Vector) throws {
        try checkReencoding(vector, decode: Hello.init(decoding:)) { $0.encoded() }
    }

    @Test("WindowUpdate re-encodes to the decoded bytes", arguments: vectors("WindowUpdate"))
    func reencodeWindowUpdate(vector: Vector) throws {
        try checkReencoding(vector, decode: WindowUpdate.init(decoding:)) { $0.encoded() }
    }

    @Test("memberwise initializers build the decoded messages", arguments: vectors("Hello"))
    func memberwiseInitializers(vector: Vector) throws {
        guard let hello = try? Hello(decoding: try inputBytes(vector)) else { return }
        let version = hello.version
        let state = hello.deviceState
        let rebuilt = Hello(
            version: FirmwareVersion(
                version: version.version,
                radioModuleStatus: version.radioModuleStatus,
                windowSize: version.windowSize,
                moduleType: version.moduleType,
                minRadioFreq: version.minRadioFreq,
                maxRadioFreq: version.maxRadioFreq,
                features: version.features
            ),
            deviceState: DeviceState(
                radio: state.radio,
                radioModuleStatus: state.radioModuleStatus,
                mode: state.mode,
                lastError: state.lastError,
                latestRssi: state.latestRssi
            )
        )
        #expect(rebuilt == hello)
        #expect(WindowUpdate(size: version.windowSize).size == version.windowSize)
    }

    private func inputBytes(_ vector: Vector) throws -> [UInt8] {
        Array(try [UInt8](hex: try #require(vector.input.bytes)).prefix(try #require(vector.input.len)))
    }

    /// The device-side encoders (used by the simulator) reproduce every message the decoders accept.
    private func checkReencoding<T>(
        _ vector: Vector,
        decode: ([UInt8]) throws(ProtocolError) -> T,
        encode: (T) -> [UInt8]
    ) throws {
        let bytes = try inputBytes(vector)
        guard let decoded = try? decode(bytes) else { return }
        #expect(encode(decoded) == bytes)
    }

    /// Android returns no value for a wrong length and throws for an unknown module type.
    private func check<T>(
        _ vector: Vector,
        decode: ([UInt8]) throws(ProtocolError) -> T,
        matches: (ValueJSON, T) throws -> Void
    ) throws {
        let bytes = try inputBytes(vector)
        switch Result(catching: { () throws(ProtocolError) in try decode(bytes) }) {
        case .success(let decoded):
            try matches(try #require(vector.expected.value), decoded)
        case .failure(.invalidLength):
            #expect(vector.expected.value == nil && vector.expected.error == nil)
        case .failure(.unknownRFModuleType):
            #expect(vector.expected.error == "invalidArgument")
        case .failure(let error):
            Issue.record("unexpected \(error)")
        }
    }
}

/// Enum case names as printed by the Android generator.
func androidName(_ status: RadioModuleStatus) -> String {
    switch status {
    case .found: "RADIO_STATUS_FOUND"
    case .notFound: "RADIO_STATUS_NOT_FOUND"
    case .unknown: "RADIO_STATUS_UNKNOWN"
    }
}

func androidName(_ mode: DeviceMode) -> String {
    switch mode {
    case .tx: "DEVICE_MODE_TX"
    case .rx: "DEVICE_MODE_RX"
    case .stopped: "DEVICE_MODE_STOPPED"
    case .unknown: "DEVICE_MODE_UNKNOWN"
    }
}

func androidName(_ type: RFModuleType) -> String {
    switch type {
    case .sa818VHF: "RF_SA818_VHF"
    case .sa818UHF: "RF_SA818_UHF"
    }
}
