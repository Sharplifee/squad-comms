import CoreLocation
import Foundation

/// Postgres columns are snake_case. Without these CodingKeys the Swift
/// property names go over the wire verbatim and PostgREST rejects the request
/// with "Could not find the 'createdAt' column of 'squads' in the schema
/// cache" — which is exactly what stranded the app on a "Couldn't connect"
/// screen. Any new property here needs a key or it will fail the same way.
struct Squad: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var joinCode: String              // 6 digits
    var createdAt: Date?              // set by the database, never by the app

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case joinCode  = "join_code"
        case createdAt = "created_at"
    }
}

/// Insert payload. Deliberately omits created_at: the column defaults to now()
/// server-side, and Swift's default Date encoding is a numeric interval rather
/// than a timestamp, which Postgres would reject even with the key mapped.
struct SquadInsert: Encodable {
    let id: UUID
    let name: String
    let joinCode: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case joinCode = "join_code"
    }
}

struct Member: Codable, Identifiable, Hashable {
    let id: UUID
    var displayName: String
    var isSpeaking: Bool = false
    var isMutedByMe: Bool = false
    /// Whether THEY can hear YOU. Independent of whether you can hear them —
    /// the two directions are genuinely separate needs. Wanting to listen to
    /// somebody without them hearing your breathing is normal; so is talking to
    /// someone whose mic is picking up a leaf blower you have muted.
    var isMutedToThem: Bool = false
    var volume: Double = 1.0      // 0...1, per-listener, local only
    var nearby: Bool = false      // CoreBluetooth RSSI signal

    /// Only populated when somebody has opted into sharing a location. The
    /// continental view needs it; nothing else does, so it stays optional.
    var latitude: Double?
    var longitude: Double?

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// What happens to your own media when someone in the squad talks.
enum DuckBehavior: String, Codable, CaseIterable, Identifiable {
    case duck        // lower to ~10%
    case pause       // full stop
    case rewind      // pause, then rewind on resume so nothing is missed
    var id: String { rawValue }

    var label: String {
        switch self {
        case .duck:   return "Lower my audio"
        case .pause:  return "Pause my audio"
        case .rewind: return "Pause and rewind"
        }
    }

    var detail: String {
        switch self {
        case .duck:   return "Music drops to a whisper while they speak, then comes straight back."
        case .pause:  return "Music stops completely, then picks up where it left off."
        case .rewind: return "Music stops, then rewinds a few seconds so you don't miss anything."
        }
    }
}

enum SessionState: Equatable {
    case idle
    /// No squad code chosen yet. The person picks one rather than being handed
    /// a generated squad they never asked for.
    case needsCode
    case connecting
    case connected
    case failed(String)
}

enum NoiseSuppression: String, Codable, CaseIterable, Identifiable {
    case none, standard, active
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none:     return "Off"
        case .standard: return "Standard"
        case .active:   return "Active"
        }
    }
    var detail: String {
        switch self {
        case .none:     return "Rawest signal. Best if your gym is quiet."
        case .standard: return "Balanced. Handles most background noise."
        case .active:   return "Strongest. Can thin out your voice."
        }
    }
}

struct Preferences: Codable, Equatable {
    var displayName: String = "Me"

    // Audio tab
    var intercomVolume: Double = 0.80
    var selfMonitor: Double = 0.20
    var autoPause: Bool = false
    var autoPauseSeconds: Double = 8
    var autoRewind: Bool = false
    var noiseSuppression: NoiseSuppression = .standard

    // Presence
    /// List gives you the sliders; tiles give you faces you can read across a
    /// room. Persisted because it is a standing preference, not a mode.
    var squadViewIsList: Bool = false
    /// Widens the proximity scan and slows the radar once a line is open.
    /// Continuous BLE scanning plus always-on VAD plus WebRTC will not survive
    /// a 90 minute session comfortably at full rate.
    var lowPowerMode: Bool = false
    /// A short tone on join, leave and end. The phone is in a pocket, so
    /// haptics and anything visual both miss entirely.
    var soundCues: Bool = true
    var ghostMode: Bool = false
    var privateSession: Bool = false
    var duckBehavior: DuckBehavior = .duck
    var duckLevel: Double = 0.10          // 10% of current volume
    var rewindSeconds: Double = 8
    var openMic: Bool = true              // VAD on; false = push to talk
    var vadOnsetDB: Float = -20
    var vadSilenceDB: Float = -40
    var trailingMS: Int = 300
}
