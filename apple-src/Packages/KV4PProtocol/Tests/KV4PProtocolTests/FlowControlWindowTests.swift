import Testing

@testable import KV4PProtocol

@Suite("Flow-control window")
struct FlowControlWindowTests {
    @Test("starts with the Android default of 1024 bytes")
    func defaultSize() async {
        #expect(await FlowControlWindow().available == 1024)
    }

    @Test("reserve subtracts the encoded frame length")
    func reserveSubtracts() async throws {
        let window = FlowControlWindow(size: 100)
        try await window.reserve(60)
        #expect(await window.available == 40)
    }

    @Test("HELLO sets the window, WINDOW_UPDATE enlarges it")
    func setAndEnlarge() async {
        let window = FlowControlWindow(size: 10)
        await window.set(4096)
        await window.enlarge(by: 100)
        #expect(await window.available == 4196)
    }

    @Test("reserve waits until a window update makes room")
    func waitsForRoom() async throws {
        let window = FlowControlWindow(size: 10)
        let sender = Task { try await window.reserve(50) }
        await window.waitForWaiters(1)
        #expect(await window.available == 10)
        await window.enlarge(by: 40)
        try await sender.value
        #expect(await window.available == 0)
        #expect(await window.waiting == 0)
    }

    @Test("waiting senders are served in order")
    func fifo() async throws {
        let window = FlowControlWindow(size: 0)
        let first = Task { try await window.reserve(30) }
        await window.waitForWaiters(1)
        let second = Task { try await window.reserve(10) }
        await window.waitForWaiters(2)
        // Room for the second but not the first: nobody overtakes the head.
        await window.set(20)
        #expect(await window.waiting == 2)
        await window.enlarge(by: 20)
        try await first.value
        try await second.value
        #expect(await window.available == 0)
    }

    @Test("a new sender queues behind waiting senders")
    func noOvertaking() async throws {
        let window = FlowControlWindow(size: 5)
        let first = Task { try await window.reserve(10) }
        await window.waitForWaiters(1)
        let second = Task { try await window.reserve(1) }
        await window.waitForWaiters(2)
        await window.enlarge(by: 6)
        try await first.value
        try await second.value
        #expect(await window.available == 0)
    }

    @Test("cancelling a waiting sender throws and frees its place")
    func cancelWhileWaiting() async {
        let window = FlowControlWindow(size: 0)
        let sender = Task { try await window.reserve(10) }
        await window.waitForWaiters(1)
        sender.cancel()
        await #expect(throws: CancellationError.self) { try await sender.value }
        #expect(await window.waiting == 0)
        #expect(await window.available == 0)
    }

    @Test("an already cancelled task does not reserve")
    func cancelledBeforeReserve() async {
        let window = FlowControlWindow(size: 0)
        let sender = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await window.reserve(10)
        }
        await #expect(throws: CancellationError.self) { try await sender.value }
        #expect(await window.waiting == 0)
    }
}

extension FlowControlWindow {
    /// Yields until `count` senders are waiting.
    func waitForWaiters(_ count: Int) async {
        while waiting < count {
            await Task.yield()
        }
    }
}
