import Foundation
import Supabase

/// Supabase: squads, membership, and LiveKit token minting via an Edge Function.
/// The LiveKit API secret NEVER ships in the app — the edge function holds it.
struct Backend {

    private var client: SupabaseClient? {
        guard let url = Config.supabaseURL, !Config.supabaseAnonKey.isEmpty else { return nil }
        return SupabaseClient(supabaseURL: url, supabaseKey: Config.supabaseAnonKey)
    }

    enum BackendError: LocalizedError {
        case notConfigured
        case codeNotFound
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Supabase isn't configured."
            case .codeNotFound:  return "No squad found with that code."
}
        }
    }

    /// - Parameter code: chosen by the person, never generated. A code you
    ///   picked is one you can say out loud across a gym floor and the other
    ///   person can type without looking; six random digits have to be read
    ///   off a screen every time.
    /// Join the squad on this code, or create it if nobody has yet.
    ///
    /// Resolved in one server-side call rather than a select-then-insert from
    /// the client. Two people typing the same new code at the same moment is a
    /// real race — at a gym it is the *expected* case, since you agree on a
    /// code and both open the app — and a client-side check would let both win
    /// and land them in different rooms with the same code on screen.
    /// Outcome of a join or create. Typed rather than a bare optional so the
    /// UI can say what actually happened — "that code is full" and "that code
    /// doesn't exist" send people to different actions.
    struct SquadOutcome: Decodable {
        let outcome: String
        let retryAfter: Int?
        let squadID: UUID?
        let squadName: String?
        let joinCode: String?

        enum CodingKeys: String, CodingKey {
            case outcome    = "r_outcome"
            case retryAfter = "r_retry_after"
            case squadID    = "r_squad_id"
            case squadName  = "r_squad_name"
            case joinCode   = "r_join_code"
        }

        var squad: Squad? {
            guard let squadID, let joinCode else { return nil }
            return Squad(id: squadID, name: squadName ?? "Squad",
                         joinCode: joinCode, createdAt: nil)
        }
    }

    /// Join an existing line. Never creates one.
    ///
    /// Joining and creating are separate calls on purpose. When a miss quietly
    /// created a squad, a brute-force sweep never registered a single failure,
    /// so the server-side backoff could never engage and the table filled with
    /// abandoned rooms.
    func joinSquad(code: String, deviceID: String) async throws -> SquadOutcome {
        guard let client else { throw BackendError.notConfigured }
        struct P: Encodable { let p_code: String; let p_device_id: String }
        let rows: [SquadOutcome] = try await client
            .rpc("join_squad", params: P(p_code: code, p_device_id: deviceID))
            .execute().value
        guard let first = rows.first else { throw BackendError.codeNotFound }
        return first
    }

    /// Open a new line on a chosen code. Refuses a code already live.
    func createSquad(code: String, name: String, deviceID: String) async throws -> SquadOutcome {
        guard let client else { throw BackendError.notConfigured }
        struct P: Encodable { let p_code: String; let p_name: String; let p_device_id: String }
        let rows: [SquadOutcome] = try await client
            .rpc("create_squad", params: P(p_code: code, p_name: name, p_device_id: deviceID))
            .execute().value
        guard let first = rows.first else { throw BackendError.notConfigured }
        return first
    }

    /// Close a line for everyone and free its code for reuse.
    func endSquad(id: UUID) async throws {
        guard let client else { throw BackendError.notConfigured }
        struct P: Encodable { let p_squad_id: String }
        _ = try await client.rpc("end_squad", params: P(p_squad_id: id.uuidString)).execute()
    }

    func squad(forCode code: String) async throws -> Squad {
        guard let client else { throw BackendError.notConfigured }
        let rows: [Squad] = try await client.from("squads")
            .select()
            .eq("join_code", value: code)
            .limit(1)
            .execute()
            .value
        guard let squad = rows.first else { throw BackendError.codeNotFound }
        return squad
    }

    func token(for squadID: UUID, displayName: String) async throws -> String {
        guard let client else { throw BackendError.notConfigured }
        struct Response: Decodable { let token: String }
        let response: Response = try await client.functions
            .invoke("mint-livekit-token",
                    options: .init(body: ["squadId": squadID.uuidString,
                                          "displayName": displayName]))
        return response.token
    }
}
