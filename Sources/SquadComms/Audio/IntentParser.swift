import Foundation
import Supabase

/// A structured voice intent. Produced either by the `parse-command` edge
/// function (real intent parsing) or by the local keyword table (fallback).
struct VoiceIntent: Equatable {

    enum Action: String, Decodable {
        case mute
        case unmute
        case muteAll
        case unmuteAll
        case setVolume
        case whosOn
        case rewind
        case leave
        case unknown
    }

    /// Where the intent came from — worth knowing in telemetry, since a sudden
    /// collapse to `.keyword` means the edge function is failing silently.
    enum Source: String {
        case model
        case keyword
    }

    let action: Action
    let volume: Double?
    let target: String?
    let confidence: Double
    let source: Source

    static let unknown = VoiceIntent(action: .unknown, volume: nil, target: nil,
                                     confidence: 0, source: .keyword)
}

/// Turns a transcribed utterance into a `VoiceIntent`.
///
/// The model call is server-side, in the `parse-command` edge function, so this
/// works on the shipping iOS release — no Foundation Models server-side language
/// model support (iOS 27) required on device. Speech transcription stays
/// on-device; only the resulting text leaves the phone.
struct IntentParser {

    /// Below this we don't act on a model intent — the keyword table gets the
    /// final say instead. Acting on a false positive mid-set is worse than
    /// missing a command.
    static let confidenceFloor = 0.6

    private var client: SupabaseClient? {
        guard let url = Config.supabaseURL, !Config.supabaseAnonKey.isEmpty else { return nil }
        return SupabaseClient(supabaseURL: url, supabaseKey: Config.supabaseAnonKey)
    }

    private struct Payload: Decodable {
        let action: VoiceIntent.Action
        let volume: Double?
        let target: String?
        let confidence: Double
    }

    /// The invoke body must be a single concrete Encodable type. A dictionary
    /// literal mixing String and [String] infers [String: Any], which is not
    /// Encodable — that is what broke the build on 2026-08-19.
    private struct Request: Encodable {
        let utterance: String
        let roster: [String]
    }

    /// Never throws. Any failure — not configured, offline, rate limited, bad
    /// response — degrades to the keyword table rather than dropping the command.
    func parse(_ utterance: String, roster: [String] = []) async -> VoiceIntent {
        let trimmed = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unknown }

        let fallback = Self.keywordIntent(for: trimmed)

        guard let client else { return fallback }

        do {
            let payload: Payload = try await client.functions
                .invoke("parse-command",
                        options: .init(body: Request(utterance: trimmed, roster: roster)))

            guard payload.confidence >= Self.confidenceFloor, payload.action != .unknown else {
                return fallback
            }

            return VoiceIntent(action: payload.action,
                               volume: payload.volume,
                               target: payload.target,
                               confidence: payload.confidence,
                               source: .model)
        } catch {
            Telemetry.event("intent_parse_fallback", ["error": error.localizedDescription])
            return fallback
        }
    }

    /// The original keyword table, kept verbatim as the fallback path.
    static func keywordIntent(for text: String) -> VoiceIntent {
        let lowered = text.lowercased()
        for command in CommandEngine.Command.allCases where lowered.hasSuffix(command.rawValue) {
            return VoiceIntent(action: command.action, volume: nil, target: nil,
                               confidence: 1, source: .keyword)
        }
        return .unknown
    }
}

extension CommandEngine.Command {
    var action: VoiceIntent.Action {
        switch self {
        case .muteAll:   return .muteAll
        case .unmuteAll: return .unmuteAll
        case .muteMe:    return .mute
        case .unmuteMe:  return .unmute
        case .rewind:    return .rewind
        case .leave:     return .leave
        }
    }
}
