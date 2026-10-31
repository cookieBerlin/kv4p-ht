import Testing

@testable import KV4PTestSupport

@Suite("Collect")
struct CollectTests {
    @Test("collects the first elements of a stream")
    func collectsPrefix() async {
        let (stream, continuation) = AsyncStream.makeStream(of: Int.self)
        [1, 2, 3].forEach { continuation.yield($0) }
        continuation.finish()
        #expect(await collect(2, from: stream) == [1, 2])
    }
}
