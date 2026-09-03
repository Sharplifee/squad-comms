import CoreBluetooth
import Foundation
import Combine

/// Who is physically near you, from CoreBluetooth RSSI.
///
/// Audio never travels over Bluetooth — it goes over WiFi/LTE through LiveKit.
/// BLE is only used to answer "how far away is this person right now", which is
/// what the radar draws. RSSI is converted to metres with the log-distance path
/// loss model; it is noisy by nature, so every reading is smoothed before it
/// reaches the UI or the dots jitter constantly.
final class ProximityEngine: NSObject, ObservableObject {

    struct Contact: Identifiable, Equatable {
        let id: UUID
        /// Survives Apple's ~15 minute MAC rotation. Without this the same
        /// person becomes a new contact four times an hour.
        var fingerprint: DeviceFingerprint?
        var rssi: Int
        var metres: Double
        var lastSeen: Date
        /// 0...1 against the currently selected range.
        var normalised: Double = 0
    }

    @Published private(set) var contacts: [Contact] = []
    @Published private(set) var isScanning = false

    /// Nine logarithmic stops. Hyper-local matters most — 100 ft is the gym
    /// floor, and that is the case this app exists for.
    static let rangeLabels  = ["100 FT", "250 FT", "500 FT", "0.25 MI", "1 MI",
                               "5 MI", "25 MI", "100 MI", "ANYWHERE"]
    /// Short forms for the tick row under the slider.
    static let rangeTicks = ["100ft", "250ft", "500ft", ".25mi", "1mi",
                             "5mi", "25mi", "100mi", "∞"]

    static let rangeMetres: [Double] = [30.5, 76.2, 152.4, 402.3, 1609.3,
                                        8046.7, 40233.6, 160934.4, 9_999_999]

    @Published var rangeIndex: Int = 1 {
        didSet { renormalise() }
    }

    var onNearbyChanged: ((Set<UUID>) -> Void)?

    private var central: CBCentralManager?
    private var peripheral: CBPeripheralManager?
    private var squadID: UUID?
    private var selfID: UUID?
    private var smoothed: [UUID: Double] = [:]
    /// Identity given to a fingerprint, so a rotated address resolves back to
    /// the contact already on the radar instead of spawning a duplicate.
    private var fingerprintIdentity: [DeviceFingerprint: UUID] = [:]
    private var pruneTimer: Timer?
    private var isSuspended = false

    private static let serviceUUID = CBUUID(string: "9F2A1C34-6B70-4E1D-9C2F-5A8E3D71B0C4")
    private static let nearThresholdRSSI = -65
    private static let txPowerAt1m = -59.0
    private static let staleAfter: TimeInterval = 12
    private static let smoothing = 0.25

    // MARK: - Lifecycle

    /// - Parameters:
    ///   - squadID: scoped so we only see our own squad, carried in the service data.
    ///   - selfID:  this device's participant identity. Advertising the squad ID
    ///              here was the bug that made the radar useless — every member
    ///              broadcast the same string, so all peers decoded to one
    ///              identity and collapsed into a single dot, and Member.nearby
    ///              could never be true for anyone.
    func start(squadID: UUID, selfID: UUID) {
        self.squadID = squadID
        self.selfID = selfID
        central = CBCentralManager(delegate: self, queue: .global(qos: .utility))
        peripheral = CBPeripheralManager(delegate: self, queue: .global(qos: .utility))
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.prune()
        }
    }

    /// Ghost mode: stop broadcasting our own identity while continuing to scan.
    /// You still see everyone; nobody sees you. Audio is untouched.
    func stopAdvertising() {
        peripheral?.stopAdvertising()
    }

    /// Backgrounded, or in low power. Scanning while the screen is off burns
    /// battery to update a radar nobody can see.
    func setSuspended(_ suspended: Bool) {
        guard suspended != isSuspended else { return }
        isSuspended = suspended
        if suspended {
            central?.stopScan()
            Task { @MainActor in self.isScanning = false }
        } else if central?.state == .poweredOn {
            beginScan()
        }
    }

    /// Duplicate discoveries are what let the radar move at all, but they also
    /// arrive constantly. In low power we drop to a single discovery per
    /// device and let the smoothing coast between updates.
    private func beginScan() {
        let duplicates = !PreferencesStore.shared.current.lowPowerMode
        central?.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: duplicates]
        )
        Task { @MainActor in self.isScanning = true }
    }

    func stop() {
        pruneTimer?.invalidate(); pruneTimer = nil
        central?.stopScan()
        peripheral?.stopAdvertising()
        central = nil
        peripheral = nil
        smoothed = [:]
        Task { @MainActor in
            self.contacts = []
            self.isScanning = false
            self.onNearbyChanged?([])
        }
    }

    // MARK: - Distance

    /// Log-distance path loss. Rough, but the right shape: every 6 dB lost is
    /// roughly double the distance.
    static func metres(fromRSSI rssi: Int) -> Double {
        pow(10, (txPowerAt1m - Double(rssi)) / 20.0)
    }

    private func renormalise() {
        let limit = Self.rangeMetres[rangeIndex]
        let updated = contacts.map { c -> Contact in
            var c = c
            c.normalised = min(c.metres / limit, 1.0)
            return c
        }
        Task { @MainActor in self.contacts = updated }
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-Self.staleAfter)
        let kept = contacts.filter { $0.lastSeen > cutoff }
        guard kept.count != contacts.count else { return }
        Task { @MainActor in
            self.contacts = kept
            self.onNearbyChanged?(Set(kept.map(\.id)))
        }
    }

    /// Resolve an advertisement to a stable identity.
    ///
    /// Exact fingerprint match wins. Failing that, fuzzy-match against known
    /// fingerprints and merge when enough segments agree — that is the case
    /// where the address has just rotated. Only when nothing matches is this
    /// treated as somebody new.
    private func identity(for advertised: UUID, fingerprint: DeviceFingerprint?) -> UUID {
        guard let fingerprint else { return advertised }

        if let known = fingerprintIdentity[fingerprint] { return known }

        for (candidate, id) in fingerprintIdentity
        where candidate.agreement(with: fingerprint) >= DeviceFingerprint.mergeThreshold {
            fingerprintIdentity[fingerprint] = id      // remember the new shape
            return id
        }

        fingerprintIdentity[fingerprint] = advertised
        return advertised
    }

    private func ingest(id: UUID, rssi: Int, fingerprint: DeviceFingerprint? = nil) {
        // Exponential smoothing on RSSI, not on distance — the conversion is
        // exponential, so smoothing after it over-weights close readings.
        let prior = smoothed[id] ?? Double(rssi)
        let value = prior + (Double(rssi) - prior) * Self.smoothing
        smoothed[id] = value

        let m = Self.metres(fromRSSI: Int(value.rounded()))
        let limit = Self.rangeMetres[rangeIndex]

        var next = contacts
        if let i = next.firstIndex(where: { $0.id == id }) {
            next[i].rssi = Int(value.rounded())
            next[i].metres = m
            next[i].lastSeen = Date()
            next[i].normalised = min(m / limit, 1.0)
        } else {
            next.append(Contact(id: id, fingerprint: fingerprint,
                                rssi: Int(value.rounded()), metres: m,
                                lastSeen: Date(), normalised: min(m / limit, 1.0)))
        }
        next.sort { $0.metres < $1.metres }

        let ids = Set(next.map(\.id))
        Task { @MainActor in
            self.contacts = next
            self.onNearbyChanged?(ids)
        }
    }
}

// MARK: - Central

extension ProximityEngine: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ manager: CBCentralManager) {
        guard manager.state == .poweredOn else {
            Task { @MainActor in self.isScanning = false }
            return
        }
        // Duplicates give a continuous RSSI stream to smooth, which is the
        // whole reason the radar can move. beginScan decides whether we can
        // afford them right now.
        guard !isSuspended else { return }
        beginScan()
    }

    func centralManager(_ manager: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        guard let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String,
              let id = UUID(uuidString: name) else { return }
        // Our own advertisement comes back through the scanner; counting it
        // would put a phantom contact on top of the centre marker.
        guard id != selfID else { return }
        guard RSSI.intValue != 127 else { return }   // 127 = unreadable
        let print = DeviceFingerprint(advertisementData: advertisementData, rssi: RSSI.intValue)
        ingest(id: identity(for: id, fingerprint: print),
               rssi: RSSI.intValue,
               fingerprint: print)
    }
}

// MARK: - Peripheral

extension ProximityEngine: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ manager: CBPeripheralManager) {
        guard manager.state == .poweredOn, let selfID else { return }
        manager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID],
            // The local name carries who this device is. Peers are matched to
            // squad members by this value, so it must be per-person.
            CBAdvertisementDataLocalNameKey: selfID.uuidString
        ])
    }
}
