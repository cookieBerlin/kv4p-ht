import Testing

@testable import KV4PProtocol

/// Checks `SMeter` against `Protocol.calculateSMeterValue` for every raw RSSI value.
@Suite("S-meter vectors")
struct SMeterVectorTests {
    struct Input: Decodable, Sendable {
        let rssi: UInt8
    }

    struct Expected: Decodable, Sendable {
        let sMeter: Int
    }

    static let vectors = (try? VectorFile<Input, Expected>.load("s-meter")) ?? []

    @Test("vector file covers every RSSI value")
    func vectorsPresent() {
        #expect(Self.vectors.count == 256)
    }

    @Test("S-meter value matches Android", arguments: vectors)
    func matchesAndroid(vector: VectorFile<Input, Expected>.Vector) {
        #expect(SMeter.value(rssi: vector.input.rssi) == vector.expected.sMeter)
    }
}
