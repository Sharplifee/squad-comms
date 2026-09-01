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
    func joinOrCreateSquad(code: String, name: String) async throws -> Squad {
        guard let client else { throw BackendError.notConfigured }
        let rows: [Squad] = try await client
            .rpc("join_or_create_squad", params: ["p_code": code, "p_name": name])
            .execute()
            .value
        guard let squad = rows.first else { throw BackendError.codeNotFound }
        return squad
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
