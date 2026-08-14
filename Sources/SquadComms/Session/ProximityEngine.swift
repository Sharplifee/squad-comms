import CoreBluetooth
import Foundation

/// CoreBluetooth RSSI as a "who is physically near me" signal.
/// Not used for transport — audio always goes over WiFi/LTE through LiveKit.
/// This only surfaces a nearby badge so you know who is actually in the room.
final class ProximityEngine: NSObject {

    var onNearbyChanged: ((Set<UUID>) -> Void)?

    private var central: CBCentralManager?
    private var peripheral: CBPeripheralManager?
    private var nearby: Set<UUID> = []
    private var squadID: UUID?

    private static let serviceUUID = CBUUID(string: "9F2A1C34-6B70-4E1D-9C2F-5A8E3D71B0C4")
    private static let nearThresholdRSSI = -65

    func start(squadID: UUID) {
        self.squadID = squadID
        central = CBCentralManager(delegate: self, queue: .global(qos: .utility))
        peripheral = CBPeripheralManager(delegate: self, queue: .global(qos: .utility))
    }

    func stop() {
        central?.stopScan()
        peripheral?.stopAdvertising()
        central = nil
        peripheral = nil
        nearby = []
        onNearbyChanged?(nearby)
    }
}

extension ProximityEngine: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ manager: CBCentralManager) {
        guard manager.state == .poweredOn else { return }
        manager.scanForPeripherals(withServices: [Self.serviceUUID],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func centralManager(_ manager: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        guard let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String,
              let id = UUID(uuidString: name) else { return }

        let isNear = RSSI.intValue > Self.nearThresholdRSSI
        let changed = isNear ? nearby.insert(id).inserted : (nearby.remove(id) != nil)
        if changed { onNearbyChanged?(nearby) }
    }
}

extension ProximityEngine: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ manager: CBPeripheralManager) {
        guard manager.state == .poweredOn, let squadID else { return }
        manager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID],
            CBAdvertisementDataLocalNameKey: squadID.uuidString
        ])
    }
}
