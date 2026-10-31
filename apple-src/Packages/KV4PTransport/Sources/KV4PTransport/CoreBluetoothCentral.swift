#if canImport(CoreBluetooth)
    import CoreBluetooth
    import KV4PProtocol

    /// Forwards between CoreBluetooth and `BLETransport` (ADR-0018). All logic lives in `BLELink`; this file is
    /// excluded from coverage (ADR-0011) and verified with the hardware checklist.
    public final class CoreBluetoothCentral: NSObject, BLECentral, @unchecked Sendable {
        public let events: AsyncStream<BLEEvent>
        private let continuation: AsyncStream<BLEEvent>.Continuation
        /// CoreBluetooth callbacks and all state below are confined to this queue.
        private let queue = DispatchQueue(label: "kv4p.ble")
        private var manager: CBCentralManager?
        private var discovered: [UUID: CBPeripheral] = [:]
        private var peripheral: CBPeripheral?
        private var tx: CBCharacteristic?
        private var rx: CBCharacteristic?
        private let serviceUUID = CBUUID(string: BLEGATT.serviceUUID)
        private let txUUID = CBUUID(string: BLEGATT.txCharacteristicUUID)
        private let rxUUID = CBUUID(string: BLEGATT.rxCharacteristicUUID)

        public override init() {
            (events, continuation) = AsyncStream.makeStream()
            super.init()
            manager = CBCentralManager(delegate: self, queue: queue)
        }

        public func perform(_ command: BLECommand) {
            queue.async { self.execute(command) }
        }

        private func execute(_ command: BLECommand) {
            switch command {
            case .scan:
                manager?.scanForPeripherals(withServices: [serviceUUID])
            case .stopScan:
                manager?.stopScan()
            case .connect(let identifier):
                discovered[identifier].map { manager?.connect($0) }
            case .discoverService:
                peripheral?.discoverServices([serviceUUID])
            case .discoverCharacteristics:
                peripheral?.services?.first { $0.uuid == serviceUUID }
                    .map { peripheral?.discoverCharacteristics([txUUID, rxUUID], for: $0) }
            case .enableNotifications:
                rx.map { peripheral?.setNotifyValue(true, for: $0) }
            case .write(let bytes, let withResponse):
                tx.map {
                    peripheral?.writeValue(Data(bytes), for: $0, type: withResponse ? .withResponse : .withoutResponse)
                }
                emit(.wrote(canSendMore: peripheral?.canSendWriteWithoutResponse ?? false))
            case .cancelConnection:
                peripheral.map { manager?.cancelPeripheralConnection($0) }
            }
        }

        private func emit(_ event: BLEEvent) {
            continuation.yield(event)
        }
    }

    extension CoreBluetoothCentral: CBCentralManagerDelegate {
        public func centralManagerDidUpdateState(_ central: CBCentralManager) {
            emit(.powerState(BLEPowerState(rawValue: central.state.rawValue) ?? .unknown))
        }

        public func centralManager(
            _ central: CBCentralManager,
            didDiscover peripheral: CBPeripheral,
            advertisementData: [String: Any],
            rssi RSSI: NSNumber
        ) {
            discovered[peripheral.identifier] = peripheral
            emit(.discovered(peripheral.identifier))
        }

        public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
            self.peripheral = peripheral
            peripheral.delegate = self
            emit(.connected)
        }

        public func centralManager(
            _ central: CBCentralManager,
            didFailToConnect peripheral: CBPeripheral,
            error: (any Error)?
        ) {
            emit(.failedToConnect)
        }

        public func centralManager(
            _ central: CBCentralManager,
            didDisconnectPeripheral peripheral: CBPeripheral,
            error: (any Error)?
        ) {
            emit(.disconnected)
        }
    }

    extension CoreBluetoothCentral: CBPeripheralDelegate {
        public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
            emit(.serviceDiscovered(peripheral.services?.contains { $0.uuid == serviceUUID } ?? false))
        }

        public func peripheral(
            _ peripheral: CBPeripheral,
            didDiscoverCharacteristicsFor service: CBService,
            error: (any Error)?
        ) {
            tx = service.characteristics?.first { $0.uuid == txUUID }
            rx = service.characteristics?.first { $0.uuid == rxUUID }
            let characteristics = tx.map { tx in
                BLECharacteristics(
                    supportsWriteWithoutResponse: tx.properties.contains(.writeWithoutResponse),
                    maximumWriteWithoutResponseLength: peripheral.maximumWriteValueLength(for: .withoutResponse),
                    maximumWriteWithResponseLength: peripheral.maximumWriteValueLength(for: .withResponse)
                )
            }
            emit(.characteristicsDiscovered(rx == nil ? nil : characteristics))
        }

        public func peripheral(
            _ peripheral: CBPeripheral,
            didUpdateNotificationStateFor characteristic: CBCharacteristic,
            error: (any Error)?
        ) {
            emit(.notificationsEnabled(error == nil && characteristic.isNotifying))
        }

        public func peripheral(
            _ peripheral: CBPeripheral,
            didUpdateValueFor characteristic: CBCharacteristic,
            error: (any Error)?
        ) {
            emit(.value(Array(characteristic.value ?? Data())))
        }

        public func peripheral(
            _ peripheral: CBPeripheral,
            didWriteValueFor characteristic: CBCharacteristic,
            error: (any Error)?
        ) {
            emit(.readyToWrite)
        }

        public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
            emit(.readyToWrite)
        }
    }
#endif
