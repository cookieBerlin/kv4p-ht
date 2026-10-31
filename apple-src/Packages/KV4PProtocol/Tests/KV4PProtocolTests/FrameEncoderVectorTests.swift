import Testing

@testable import KV4PProtocol

/// Checks `FrameEncoder` against the frames written by the Android `Protocol.Sender`.
@Suite("Frame encoder vectors")
struct FrameEncoderVectorTests {
    struct Input: Decodable, Sendable {
        let call: String
        let payload: String?
        let len: Int?
        let freqTx: Float?
        let bandwidth: Int?
        let ctcssTx: Int?
        let value: Int?
        let state: MessageVectorTests.StateJSON?
    }

    struct Expected: Decodable, Sendable {
        let frames: [String]?
        let error: String?
    }

    typealias Vector = VectorFile<Input, Expected>.Vector

    static let vectors = (try? VectorFile<Input, Expected>.load("kiss-sender")) ?? []

    @Test("vector file covers every send call")
    func vectorsPresent() {
        let calls = Set(Self.vectors.map(\.input.call))
        #expect(
            calls == ["txAx25", "txAudio", "txDigital", "txAx25OnFrequency", "setKissTxDelay", "sendDesiredState"]
        )
    }

    @Test("frame matches Android", arguments: vectors)
    func matchesAndroid(vector: Vector) throws {
        let input = vector.input
        let frame: [UInt8]?
        do throws(ProtocolError) {
            frame = try encode(input)
        } catch {
            #expect(vector.expected.error == "invalidArgument", "\(error)")
            return
        }
        let expected = try (vector.expected.frames ?? []).map { try [UInt8](hex: $0) }
        #expect(frame.map { [$0] } ?? [] == expected)
    }

    /// Returns `nil` for inputs the Swift API makes unrepresentable (e.g. an out-of-range TXDELAY).
    private func encode(_ input: Input) throws(ProtocolError) -> [UInt8]? {
        let payload = (try? [UInt8](hex: input.payload ?? "")) ?? []
        switch input.call {
        case "txAx25":
            return try FrameEncoder.ax25(payload)
        case "txAudio":
            return FrameEncoder.txAudio(payload.prefix(input.len ?? 0))
        case "txDigital":
            return FrameEncoder.txDigital(payload)
        case "txAx25OnFrequency":
            return try FrameEncoder.ax25(
                payload,
                onFrequency: input.freqTx ?? 0,
                bandwidth: UInt8(input.bandwidth ?? 0),
                ctcssTx: UInt8(input.ctcssTx ?? 0)
            )
        case "setKissTxDelay":
            guard let value = UInt8(exactly: input.value ?? -1) else {
                throw .payloadTooLong(maximum: Int(UInt8.max), actual: input.value ?? -1)
            }
            return FrameEncoder.kissTxDelay(value)
        default:
            return input.state.map { FrameEncoder.desiredState($0.radioState) }
        }
    }
}
