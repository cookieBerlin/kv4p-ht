import Foundation
import Testing

@testable import KV4PTransport

@Suite("BLE link")
struct BLELinkTests {
    static let device = UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()
    static let other = UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID()
    static let characteristics = BLECharacteristics(
        supportsWriteWithoutResponse: true,
        maximumWriteWithoutResponseLength: 5,
        maximumWriteWithResponseLength: 3
    )

    /// A link that went through the whole connection sequence.
    static func connected(_ characteristics: BLECharacteristics = characteristics) -> BLELink {
        var link = BLELink()
        _ = link.handle(.powerState(.poweredOn))
        _ = link.connect(to: nil)
        for event: BLEEvent in [
            .discovered(device), .connected, .serviceDiscovered(true), .characteristicsDiscovered(characteristics),
            .notificationsEnabled(true),
        ] {
            _ = link.handle(event)
        }
        return link
    }

    @Test("the connection sequence of the protocol spec §1.1")
    func connectionSequence() {
        var link = BLELink()
        #expect(link.state == .disconnected)
        #expect(link.handle(.powerState(.poweredOn)).isEmpty)
        #expect(link.connect(to: nil) == [.scan])
        #expect(link.state == .connecting)
        #expect(link.handle(.discovered(Self.device)) == [.stopScan, .connect(Self.device)])
        #expect(link.handle(.connected) == [.discoverService])
        #expect(link.handle(.serviceDiscovered(true)) == [.discoverCharacteristics])
        #expect(link.handle(.characteristicsDiscovered(Self.characteristics)) == [.enableNotifications])
        #expect(link.state == .connecting)
        #expect(link.handle(.notificationsEnabled(true)).isEmpty)
        #expect(link.state == .connected)
    }

    @Test("scanning starts once Bluetooth is powered on")
    func waitsForPower() {
        var link = BLELink()
        #expect(link.connect(to: nil).isEmpty)
        #expect(link.handle(.powerState(.resetting)).isEmpty)
        #expect(link.state == .connecting)
        #expect(link.handle(.powerState(.poweredOn)) == [.scan])
    }

    @Test("connecting while connecting does nothing")
    func connectTwice() {
        var link = BLELink()
        _ = link.handle(.powerState(.poweredOn))
        _ = link.connect(to: nil)
        #expect(link.connect(to: nil).isEmpty)
    }

    @Test("a target peripheral ignores other devices")
    func targetPeripheral() {
        var link = BLELink()
        _ = link.handle(.powerState(.poweredOn))
        _ = link.connect(to: Self.device)
        #expect(link.handle(.discovered(Self.other)).isEmpty)
        #expect(link.handle(.discovered(Self.device)) == [.stopScan, .connect(Self.device)])
    }

    @Test(
        "unusable Bluetooth fails the connection",
        arguments: [BLEPowerState.unsupported, .unauthorized, .poweredOff]
    )
    func bluetoothUnavailable(power: BLEPowerState) {
        var link = BLELink()
        _ = link.connect(to: nil)
        #expect(link.handle(.powerState(power)).isEmpty)
        #expect(link.state == .failed(.bluetoothUnavailable(power)))
    }

    @Test("powering off while connected fails the connection")
    func poweredOffWhileConnected() {
        var link = Self.connected()
        _ = link.handle(.powerState(.poweredOff))
        #expect(link.state == .failed(.bluetoothUnavailable(.poweredOff)))
    }

    @Test("a failed connection attempt")
    func failedToConnect() {
        var link = BLELink()
        _ = link.handle(.powerState(.poweredOn))
        _ = link.connect(to: nil)
        _ = link.handle(.discovered(Self.device))
        #expect(link.handle(.failedToConnect).isEmpty)
        #expect(link.state == .failed(.connectionFailed))
    }

    @Test("a missing service or characteristic cancels the connection")
    func missingServiceOrCharacteristic() {
        var link = BLELink()
        _ = link.handle(.powerState(.poweredOn))
        _ = link.connect(to: nil)
        _ = link.handle(.discovered(Self.device))
        _ = link.handle(.connected)
        #expect(link.handle(.serviceDiscovered(false)) == [.cancelConnection])
        #expect(link.state == .failed(.serviceNotFound))

        _ = link.connect(to: nil)
        _ = link.handle(.discovered(Self.device))
        _ = link.handle(.connected)
        _ = link.handle(.serviceDiscovered(true))
        #expect(link.handle(.characteristicsDiscovered(nil)) == [.cancelConnection])
        #expect(link.state == .failed(.serviceNotFound))
    }

    @Test("a refused notify subscription cancels the connection")
    func subscriptionFailed() {
        var link = BLELink()
        _ = link.handle(.powerState(.poweredOn))
        _ = link.connect(to: nil)
        for event: BLEEvent in [
            .discovered(Self.device), .connected, .serviceDiscovered(true),
            .characteristicsDiscovered(Self.characteristics),
        ] {
            _ = link.handle(event)
        }
        #expect(link.handle(.notificationsEnabled(false)) == [.cancelConnection])
        #expect(link.state == .failed(.subscriptionFailed))
    }

    @Test("losing the connection fails it and drops pending writes")
    func connectionLost() {
        var link = Self.connected()
        _ = link.send(Array(0..<20))
        #expect(link.handle(.disconnected).isEmpty)
        #expect(link.state == .failed(.connectionLost))
        _ = link.connect(to: nil)
        _ = link.handle(.discovered(Self.device))
        for event: BLEEvent in [
            .connected, .serviceDiscovered(true), .characteristicsDiscovered(Self.characteristics),
        ] {
            _ = link.handle(event)
        }
        #expect(link.handle(.notificationsEnabled(true)).isEmpty)
    }

    @Test("disconnecting stops scanning or cancels the connection")
    func disconnect() {
        var idle = BLELink()
        #expect(idle.disconnect().isEmpty)

        var scanning = BLELink()
        _ = scanning.handle(.powerState(.poweredOn))
        _ = scanning.connect(to: nil)
        #expect(scanning.disconnect() == [.stopScan])
        #expect(scanning.state == .disconnected)

        var waiting = BLELink()
        _ = waiting.connect(to: nil)
        #expect(waiting.disconnect().isEmpty)

        var connected = Self.connected()
        #expect(connected.disconnect() == [.cancelConnection])
        #expect(connected.handle(.disconnected).isEmpty)
        #expect(connected.state == .disconnected)
    }

    @Test("events outside their phase are ignored")
    func unexpectedEvents() {
        var link = BLELink()
        _ = link.handle(.powerState(.poweredOn))
        _ = link.connect(to: nil)
        for event: BLEEvent in [
            .connected, .failedToConnect, .serviceDiscovered(true), .characteristicsDiscovered(nil),
            .notificationsEnabled(true), .readyToWrite, .wrote(canSendMore: true), .value([1]),
            .powerState(.poweredOn),
        ] {
            #expect(link.handle(event).isEmpty, "\(event)")
        }
        #expect(link.state == .connecting)
        var connected = Self.connected()
        #expect(connected.handle(.discovered(Self.other)).isEmpty)
    }

    @Test("writes are chunked and wait until the adapter can send more")
    func writeWithoutResponse() {
        var link = Self.connected()
        #expect(link.send(Array(0..<12)) == [.write([0, 1, 2, 3, 4], withResponse: false)])
        #expect(link.send([12]).isEmpty)
        #expect(link.handle(.wrote(canSendMore: true)) == [.write([5, 6, 7, 8, 9], withResponse: false)])
        #expect(link.handle(.wrote(canSendMore: false)).isEmpty)
        #expect(link.handle(.readyToWrite) == [.write([10, 11, 12], withResponse: false)])
        #expect(link.handle(.wrote(canSendMore: true)).isEmpty)
        #expect(link.send([13]) == [.write([13], withResponse: false)])
    }

    @Test("without Write Without Response each chunk waits for its response")
    func writeWithResponse() {
        var characteristics = Self.characteristics
        characteristics.supportsWriteWithoutResponse = false
        var link = Self.connected(characteristics)
        #expect(link.send(Array(0..<5)) == [.write([0, 1, 2], withResponse: true)])
        #expect(link.handle(.wrote(canSendMore: true)).isEmpty)
        #expect(link.handle(.readyToWrite) == [.write([3, 4], withResponse: true)])
    }

    @Test("sending without a connection does nothing")
    func sendWhileDisconnected() {
        var link = BLELink()
        #expect(link.send([1, 2, 3]).isEmpty)
    }
}
