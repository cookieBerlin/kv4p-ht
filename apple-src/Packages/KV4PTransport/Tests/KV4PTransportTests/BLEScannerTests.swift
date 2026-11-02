import Foundation
import KV4PTestSupport
import Testing

@testable import KV4PTransport

/// The list of radios to choose from, independent of the connection (ADR-0038).
@Suite("BLE scanner")
struct BLEScannerTests {
    static let first = BLEDevice(id: FakeCentral.device, name: "kv4p HT")
    static let second = BLEDevice(
        id: UUID(uuidString: "00000000-0000-0000-0000-00000000B2C3") ?? UUID(),
        name: "A radio"
    )

    @Test("a device shows its name and the end of its ID, so that equal names differ")
    func label() {
        #expect(Self.first.label == "kv4p HT (00AA)")
        #expect(Self.second.label == "A radio (B2C3)")
    }

    @Test("radios are listed by label, once each, with their latest name")
    func lists() async {
        let central = FakeCentral(responses: { $0 == .scan ? [.advertised(Self.first), .advertised(Self.second)] : [] })
        let scanner = BLEScanner { central }
        var results = scanner.scan().makeAsyncIterator()
        await central.waitFor(.scan)
        var latest = await results.next()
        if latest?.count == 1 { latest = await results.next() }
        #expect(latest == [Self.second, Self.first])

        central.emit(.advertised(Self.second))
        let renamed = BLEDevice(id: Self.first.id, name: "Base")
        central.emit(.advertised(renamed))
        #expect(await results.next() == [Self.second, renamed].sorted { $0.label < $1.label })
    }

    @Test("the scan waits until Bluetooth is on")
    func waitsForPower() async {
        let central = FakeCentral(power: .poweredOff, responses: { _ in [] })
        let scanner = BLEScanner { central }
        let stream = scanner.scan()
        central.emit(.discovered(FakeCentral.device))
        central.emit(.powerState(.poweredOn))
        await central.waitFor(.scan)
        #expect(central.commands == [.scan])
        withExtendedLifetime(stream) {}
    }

    @Test("ending the scan stops it")
    func stops() async {
        let central = FakeCentral(responses: { _ in [] })
        let scanner = BLEScanner { central }
        let task = Task {
            for await _ in scanner.scan() {}
        }
        await central.waitFor(.scan)
        task.cancel()
        #expect(await eventually { central.commands.contains(.stopScan) })
    }

    @Test("the link ignores what the scanner needs")
    func linkIgnoresAdvertisement() {
        var link = BLELink()
        _ = link.connect(to: nil)
        #expect(link.handle(.advertised(Self.first)).isEmpty)
        #expect(link.state == .connecting)
    }
}
