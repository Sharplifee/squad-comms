import CoreBluetooth
import Foundation

/// Recognises the same physical phone across Apple's MAC address rotation.
///
/// iPhones rotate their Bluetooth address roughly every 15 minutes. Keying a
/// contact on `peripheral.identifier` therefore produces a brand new entry for
/// the same person every quarter of an hour — on the radar their dot vanishes
/// and reappears somewhere else, which reads as a bug and is impossible to
/// diagnose from a gym floor.
///
/// The fix, carried over from the BLE candidate engine in LiveActivityLab: build
/// a soft fingerprint out of advertisement traits that survive rotation, and
/// fuzzy-merge two sightings when enough segments agree. None of these traits is
/// unique on its own; together they are stable enough to hold identity for the
/// length of a training session, which is all this needs to do.
struct DeviceFingerprint: Hashable {

    /// Length of the manufacturer payload. Stable per device model and iOS
    /// version, and it does not change when the address rotates.
    let payloadLength: Int
    /// Apple continuity message type, e.g. nearby-info vs handoff.
    let messageType: UInt8
    /// Status/flags byte from the continuity payload.
    let statusBits: UInt8
    /// Advertised transmit power. Fixed per hardware model.
    let txPower: Int?
    /// Whether the advertisement carried an Apple manufacturer ID (0x004C).
    let isApple: Bool

    /// How many segments two fingerprints agree on.
    func agreement(with other: DeviceFingerprint) -> Int {
        var score = 0
        if payloadLength == other.payloadLength { score += 1 }
        if messageType   == other.messageType   { score += 1 }
        if statusBits    == other.statusBits    { score += 1 }
        if txPower       == other.txPower, txPower != nil { score += 1 }
        if isApple       == other.isApple, isApple { score += 1 }
        return score
    }

    /// Two or more agreeing segments is the merge threshold. One is noise —
    /// payload length alone matches half the iPhones in a commercial gym.
    static let mergeThreshold = 3

    /// Build a fingerprint from a CoreBluetooth advertisement.
    init?(advertisementData: [String: Any], rssi: Int) {
        let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let apple = (mfg?.count ?? 0) >= 2 && mfg![0] == 0x4C && mfg![1] == 0x00

        // Without manufacturer data there is nothing stable to hold on to, so
        // fall back to identity-based tracking rather than merging blindly.
        guard let mfg, mfg.count >= 4 else { return nil }

        self.payloadLength = mfg.count
        self.messageType   = mfg.count > 2 ? mfg[2] : 0
        self.statusBits    = mfg.count > 4 ? mfg[4] : 0
        self.txPower       = advertisementData[CBAdvertisementDataTxPowerLevelKey] as? Int
        self.isApple       = apple
    }
}
