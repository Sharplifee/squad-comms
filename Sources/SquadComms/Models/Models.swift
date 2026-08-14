import Foundation

struct Squad: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var joinCode: String          // 6 digits
    var createdAt: Date
}

struct Member: Codable, Identifiable, Hashable {
    let id: UUID
    var displayName: String
    var isSpeaking: Bool = false
    var isMutedByMe: Bool = false
    var volume: Double = 1.0      // 0...1, per-listener, local only
    var nearby: Bool = false      // CoreBluetooth RSSI signal
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
    case connecting
    case connected
    case failed(String)
}

struct Preferences: Codable {
    var displayName: String = "Me"
    var duckBehavior: DuckBehavior = .duck
    var duckLevel: Double = 0.10          // 10% of current volume
    var rewindSeconds: Double = 8
    var voiceCommandsEnabled: Bool = true
    var openMic: Bool = true              // VAD on; false = push to talk
    var vadOnsetDB: Float = -20
    var vadSilenceDB: Float = -40
    var trailingMS: Int = 300
}
