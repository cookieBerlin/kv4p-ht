import Foundation
import Testing

@testable import KV4PProtocol

@Suite("BLE GATT")
struct BLEGATTTests {
    /// `BluedroidBleKissGattStream.h`: one 128-bit base, the first field numbers service, TX and RX.
    @Test("service and characteristics share the firmware UUID base")
    func uuids() throws {
        let uuids = [BLEGATT.serviceUUID, BLEGATT.txCharacteristicUUID, BLEGATT.rxCharacteristicUUID]
        #expect(uuids.allSatisfy { UUID(uuidString: $0) != nil })
        #expect(uuids.map { $0.prefix(8) } == ["00000001", "00000002", "00000003"])
        #expect(Set(uuids.map { $0.dropFirst(8) }) == ["-ba2a-46c9-ae49-01b0961f68bb"])
    }
}
