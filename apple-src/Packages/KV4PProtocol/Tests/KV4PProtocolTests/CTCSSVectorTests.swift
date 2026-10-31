import KV4PTestSupport
import Testing

@testable import KV4PProtocol

/// Checks `CTCSS` against the Android `ToneHelper`.
@Suite("CTCSS vectors")
struct CTCSSVectorTests {
    struct Tone: Decodable, Sendable {
        let label: String
        let index: Int
    }

    struct Input: Decodable, Sendable {
        let type: String
        let tone: String?
    }

    struct Expected: Decodable, Sendable {
        let tones: [Tone]?
        let normalized: String?
        let index: Int?
    }

    typealias Vector = VectorFile<Input, Expected>.Vector

    static let vectors = (try? VectorFile<Input, Expected>.load("ctcss", from: .module)) ?? []

    @Test("the tone table matches Android, index 0 is no tone")
    func table() throws {
        let tones = try #require(Self.vectors.first { $0.input.type == "table" }?.expected.tones)
        #expect(CTCSS.labels == tones.map(\.label))
        #expect(tones.map(\.index) == Array(tones.indices))
        for tone in tones {
            #expect(CTCSS.label(for: UInt8(tone.index)) == tone.label)
        }
        #expect(CTCSS.label(for: UInt8(tones.count)) == nil)
    }

    @Test("entered tones are normalised like Android", arguments: vectors.filter { $0.input.type == "normalize" })
    func normalize(vector: Vector) throws {
        let input = try #require(vector.input.tone)
        #expect(CTCSS.normalize(input) == vector.expected.normalized)
        #expect(CTCSS.index(of: input).map(Int.init) == vector.expected.index)
    }
}
