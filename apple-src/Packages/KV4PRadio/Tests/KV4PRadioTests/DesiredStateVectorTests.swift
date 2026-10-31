import KV4PProtocol
import KV4PTestSupport
import Testing

@testable import KV4PRadio

/// Replays the scripts of the Android `RadioModuleController` against `DesiredStateController`.
@Suite("Desired state vectors")
struct DesiredStateVectorTests {
    struct Call: Decodable, Sendable {
        let call: String
        let bytes: String?
        let int: Int?
        let float: Float?
        let bool: Bool?
        let pre: Bool?
        let high: Bool?
        let low: Bool?
    }

    struct Outcome: Decodable, Sendable {
        let sent: [String]
        let inSync: Bool
    }

    struct Input: Decodable, Sendable {
        let steps: [Call]
    }

    struct Expected: Decodable, Sendable {
        let steps: [Outcome]
    }

    typealias Vector = VectorFile<Input, Expected>.Vector

    static let vectors = (try? VectorFile<Input, Expected>.load("desired-state", from: .module)) ?? []

    @Test("vector file is present")
    func vectorsPresent() {
        #expect(Self.vectors.count >= 16)
    }

    @Test("each step sends the same frames and reaches the same sync state as Android", arguments: vectors)
    func replay(vector: Vector) throws {
        var controller = DesiredStateController()
        for (index, (call, outcome)) in zip(vector.input.steps, vector.expected.steps).enumerated() {
            try apply(call, to: &controller)
            let sent = controller.takeOutgoing().map { FrameEncoder.desiredState($0) }
            #expect(sent == (try outcome.sent.map { try [UInt8](hex: $0) }), "step \(index) \(call.call)")
            #expect(controller.isAppliedStateInSync == outcome.inSync, "step \(index) \(call.call)")
        }
    }

    private func apply(_ call: Call, to controller: inout DesiredStateController) throws {
        let byte = UInt8(truncatingIfNeeded: call.int ?? 0)
        let flag = call.bool ?? false
        switch call.call {
        case "attach": controller.attach()
        case "detach": controller.detach()
        case "ready": controller.markReady()
        case "seed": controller.seed(try DeviceState(decoding: try [UInt8](hex: try #require(call.bytes))))
        case "deviceState": controller.update(try DeviceState(decoding: try [UInt8](hex: try #require(call.bytes))))
        case "firmware": controller.seed(try FirmwareVersion(decoding: try [UInt8](hex: try #require(call.bytes))))
        case "pttDown": controller.setPTT(true)
        case "pttUp": controller.setPTT(false)
        case "begin": controller.beginUpdate()
        case "end": controller.endUpdate()
        case "bandwidth": controller.setBandwidth(byte)
        case "txFrequency": controller.setTxFrequency(try #require(call.float))
        case "rxFrequency": controller.setRxFrequency(try #require(call.float))
        case "memoryId": controller.setMemoryId(Int32(try #require(call.int)))
        case "txTone": controller.setTxTone(byte)
        case "rxTone": controller.setRxTone(byte)
        case "squelch": controller.setSquelch(byte)
        case "filters":
            controller.setFilters(pre: call.pre ?? false, high: call.high ?? false, low: call.low ?? false)
        case "highPower": controller.setHighPower(flag)
        case "rssi": controller.setRSSI(flag)
        case "txAllowed": controller.setTXAllowed(flag)
        case "freeDv": controller.setFreeDV(flag)
        case "openAudio": controller.openAudio()
        case "closeAudio": controller.closeAudio()
        case "stop": controller.stop()
        default: Issue.record("unknown call \(call.call)")
        }
    }
}
