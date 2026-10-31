#if canImport(CoreBluetooth)
    import CoreBluetooth
    import KV4PProtocol
    import KV4PTransport

    /// Forwards between `CBPeripheralManager` and `SimulatorPeripheral` (ADR-0018). All logic lives in
    /// `PeripheralLink`; this file is excluded from coverage (ADR-0011).
    public final class CoreBluetoothPeripheralManager: NSObject, BLEPeripheralManager, @unchecked Sendable {
        public let events: AsyncStream<PeripheralEvent>
        private let continuation: AsyncStream<PeripheralEvent>.Continuation
        /// CoreBluetooth callbacks and all state below are confined to this queue.
        private let queue = DispatchQueue(label: "kv4p.peripheral")
        private let localName: String
        private let serviceUUID = CBUUID(string: BLEGATT.serviceUUID)
        private let tx = CBMutableCharacteristic(
            type: CBUUID(string: BLEGATT.txCharacteristicUUID),
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )
        private let rx = CBMutableCharacteristic(
            type: CBUUID(string: BLEGATT.rxCharacteristicUUID),
            properties: [.read, .notify],
            value: nil,
            permissions: [.readable]
        )
        private var manager: CBPeripheralManager?
        private var central: CBCentral?

        /// `localName` is advertised like the firmware's `kv4p-XXXXXX`.
        public init(localName: String = "kv4p-000000") {
            self.localName = localName
            (events, continuation) = AsyncStream.makeStream()
            super.init()
            manager = CBPeripheralManager(delegate: self, queue: queue)
        }

        public func perform(_ command: PeripheralCommand) {
            queue.async { self.execute(command) }
        }

        private func execute(_ command: PeripheralCommand) {
            switch command {
            case .addService:
                let service = CBMutableService(type: serviceUUID, primary: true)
                service.characteristics = [tx, rx]
                manager?.add(service)
            case .startAdvertising:
                manager?.startAdvertising([
                    CBAdvertisementDataServiceUUIDsKey: [serviceUUID], CBAdvertisementDataLocalNameKey: localName,
                ])
            case .stopAdvertising:
                manager?.stopAdvertising()
            case .notify(let bytes):
                let sent = manager?.updateValue(Data(bytes), for: rx, onSubscribedCentrals: central.map { [$0] })
                emit(.notified(sent ?? false))
            }
        }

        private func emit(_ event: PeripheralEvent) {
            continuation.yield(event)
        }
    }

    extension CoreBluetoothPeripheralManager: CBPeripheralManagerDelegate {
        public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
            emit(.powerState(BLEPowerState(rawValue: peripheral.state.rawValue) ?? .unknown))
        }

        public func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: (any Error)?)
        {
            emit(.serviceAdded(error == nil))
        }

        public func peripheralManager(
            _ peripheral: CBPeripheralManager,
            central: CBCentral,
            didSubscribeTo characteristic: CBCharacteristic
        ) {
            self.central = central
            emit(.subscribed(maximumUpdateLength: central.maximumUpdateValueLength))
        }

        public func peripheralManager(
            _ peripheral: CBPeripheralManager,
            central: CBCentral,
            didUnsubscribeFrom characteristic: CBCharacteristic
        ) {
            self.central = nil
            emit(.unsubscribed)
        }

        public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
            requests.forEach { emit(.write(Array($0.value ?? Data()))) }
            requests.first.map { peripheral.respond(to: $0, withResult: .success) }
        }

        public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
            request.value = Data()
            peripheral.respond(to: request, withResult: .success)
        }

        public func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
            emit(.readyToUpdate)
        }
    }
#endif
