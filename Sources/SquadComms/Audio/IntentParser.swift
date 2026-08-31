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

        guard let client else {
            Log.commands.error("IntentParser: Supabase not configured — keyword fallback only (action \(fallback.action.rawValue, privacy: .public))")
            return fallback
        }

        do {
            let payload: Payload = try await client.functions
                .invoke("parse-command",
                        options: .init(body: Request(utterance: trimmed, roster: roster)))

            guard payload.confidence >= Self.confidenceFloor, payload.action != .unknown else {
                Log.commands.info("model returned \(payload.action.rawValue, privacy: .public) @ \(payload.confidence, privacy: .public) — below floor \(Self.confidenceFloor, privacy: .public) or unknown, using keyword fallback")
                return fallback
            }

            return VoiceIntent(action: payload.action,
                               volume: payload.volume,
                               target: payload.target,
                               confidence: payload.confidence,
                               source: .model)
        } catch {
            // parse-command answered 401 to every request the app ever made:
            // the function called supabase.auth.getUser() and rejected when
            // there was no user, but squad comms has no sign-in, so there was
            // never going to be one. Log loudly — a silent collapse to the
            // keyword table is exactly what hid this for six releases.
            Log.commands.error("parse-command FAILED: \(error.localizedDescription, privacy: .public) — falling back to keyword (action \(fallback.action.rawValue, privacy: .public))")
            Telemetry.event("intent_parse_fallback", ["error": error.localizedDescription])
            return fallback
        }
    }

    /// The keyword table as the fallback path. Shares `CommandEngine.match` so
    /// the two tables cannot drift, and so this path also gets the longest-first
    /// ordering fix — iterating `allCases` in declaration order resolved
    /// "unmute all" to `muteAll`, because "unmute all" has "mute all" as a suffix.
    /// This runs on a completed utterance, so bare words are in scope.
    static func keywordIntent(for text: String) -> VoiceIntent {
        guard let command = CommandEngine.match(text.lowercased(), isFinal: true) else {
            return .unknown
        }
        return VoiceIntent(action: command.action, volume: nil, target: nil,
                           confidence: 1, source: .keyword)
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
