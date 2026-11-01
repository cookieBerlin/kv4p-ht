import Testing

@testable import KV4PTestSupport

@Suite("Fake serial port")
struct FakeSerialPortTests {
    @Test("waiting for a call returns once it was made")
    func waitForCall() async {
        let port = FakeSerialPort()
        let waiter = Task { await port.waitFor(.close) }
        for _ in 0..<1000 {
            await Task.yield()  // the waiter spins meanwhile
        }
        port.close()
        await waiter.value
        #expect(port.calls == [.close])
    }
}
