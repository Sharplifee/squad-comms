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

    func createSquad(name: String) async throws -> Squad {
        guard let client else { throw BackendError.notConfigured }
        let code = String(format: "%06d", Int.random(in: 0...999_999))
        let squad = Squad(id: UUID(), name: name, joinCode: code, createdAt: Date())
        try await client.from("squads").insert(squad).execute()
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
