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
        /// Whether this device opened the line. The only thing a creator can
        /// do that others cannot is close it for everybody.
        let isCreator: Bool?

        enum CodingKeys: String, CodingKey {
            case outcome    = "r_outcome"
            case retryAfter = "r_retry_after"
            case squadID    = "r_squad_id"
            case squadName  = "r_squad_name"
            case joinCode   = "r_join_code"
            case isCreator  = "r_is_creator"
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
        struct P: Encodable {
            let p_code: String; let p_device_id: String; let p_display_name: String
        }
        let rows: [SquadOutcome] = try await client
            .rpc("join_squad", params: P(p_code: code, p_device_id: deviceID,
                                        p_display_name: PreferencesStore.shared.current.displayName))
            .execute().value
        guard let first = rows.first else { throw BackendError.codeNotFound }
        return first
    }

    /// Open a new line on a chosen code. Refuses a code already live.
    func createSquad(code: String, name: String, deviceID: String) async throws -> SquadOutcome {
        guard let client else { throw BackendError.notConfigured }
        struct P: Encodable {
            let p_code: String; let p_name: String
            let p_device_id: String; let p_display_name: String
        }
        let rows: [SquadOutcome] = try await client
            .rpc("create_squad", params: P(p_code: code, p_name: name, p_device_id: deviceID,
                                          p_display_name: PreferencesStore.shared.current.displayName))
            .execute().value
        guard let first = rows.first else { throw BackendError.notConfigured }
        return first
    }

    /// Tell the server we are still here.
    ///
    /// Without a heartbeat a force-quit leaves somebody occupying a seat
    /// forever, and a cap that counts ghosts starts locking out the very
    /// people it was meant to protect.
    func heartbeat(squadID: UUID, deviceID: String) async {
        guard let client else { return }
        struct P: Encodable { let p_squad_id: String; let p_device_id: String }
        _ = try? await client.rpc("heartbeat",
            params: P(p_squad_id: squadID.uuidString, p_device_id: deviceID)).execute()
    }

    /// Step out. The last person out closes the line, so its code is released
    /// immediately rather than reserved for twelve hours after everyone left.
    func leaveSquad(squadID: UUID, deviceID: String) async {
        guard let client else { return }
        struct P: Encodable { let p_squad_id: String; let p_device_id: String }
        _ = try? await client.rpc("leave_squad",
            params: P(p_squad_id: squadID.uuidString, p_device_id: deviceID)).execute()
    }

    /// Close a line for everyone and free its code for reuse.
    /// Close a line for everyone. Refused server-side unless this device
    /// opened it, so hiding the button is a courtesy rather than the control.
    @discardableResult
    func endSquad(id: UUID, deviceID: String) async throws -> Bool {
        guard let client else { throw BackendError.notConfigured }
        struct P: Encodable { let p_squad_id: String; let p_device_id: String }
        let allowed: Bool = try await client
            .rpc("end_squad", params: P(p_squad_id: id.uuidString, p_device_id: deviceID))
            .execute().value
        return allowed
    }

    // MARK: - Contacts

    struct ContactRow: Decodable {
        let phoneHash: String
        let displayName: String
        let lastSeenAt: Date?

        enum CodingKeys: String, CodingKey {
            case phoneHash   = "phone_hash"
            case displayName = "display_name"
            case lastSeenAt  = "last_seen_at"
        }
    }

    /// Which of these hashes belong to somebody who has the app. Only hashes
    /// cross the wire — the server cannot recover a number from one, and
    /// cannot be used to enumerate users, because you can only ask about
    /// hashes you already hold.
    func matchContacts(hashes: [String]) async throws -> [ContactRow] {
        guard let client else { throw BackendError.notConfigured }
        struct P: Encodable { let p_hashes: [String] }
        return try await client
            .rpc("match_contacts", params: P(p_hashes: hashes))
            .execute().value
    }

    func registerDevice(deviceID: String, displayName: String,
                        phoneHash: String?, ghost: Bool) async throws {
        guard let client else { throw BackendError.notConfigured }
        struct P: Encodable {
            let p_device_id: String
            let p_display_name: String
            let p_phone_hash: String?
            let p_ghost: Bool
            let p_identity: String
        }
        _ = try await client.rpc("register_device", params: P(
            p_device_id: deviceID, p_display_name: displayName,
            p_phone_hash: phoneHash, p_ghost: ghost, p_identity: deviceID
        )).execute()
    }

    // MARK: - Safety

    struct BlockedRow: Decodable, Identifiable {
        let deviceID: String
        let displayName: String
        let blockedAt: Date?
        var id: String { deviceID }

        enum CodingKeys: String, CodingKey {
            case deviceID    = "device_id"
            case displayName = "display_name"
            case blockedAt   = "blocked_at"
        }
    }

    /// Reporting always blocks as well. Asking "and would you also like to
    /// stop hearing them?" immediately after somebody reports abuse is a bad
    /// question.
    func report(reporter: String, reported: String, squadID: UUID?,
                reason: String, detail: String?) async throws {
        guard let client else { throw BackendError.notConfigured }
        struct P: Encodable {
            let p_reporter: String; let p_reported: String
            let p_squad: String?;   let p_reason: String; let p_detail: String?
        }
        _ = try await client.rpc("report_device", params: P(
            p_reporter: reporter, p_reported: reported,
            p_squad: squadID?.uuidString, p_reason: reason, p_detail: detail
        )).execute()
    }

    func block(blocker: String, blocked: String) async throws {
        guard let client else { throw BackendError.notConfigured }
        struct P: Encodable { let p_blocker: String; let p_blocked: String }
        _ = try await client.rpc("block_device", params: P(p_blocker: blocker, p_blocked: blocked)).execute()
    }

    func unblock(blocker: String, blocked: String) async throws {
        guard let client else { throw BackendError.notConfigured }
        struct P: Encodable { let p_blocker: String; let p_blocked: String }
        _ = try await client.rpc("unblock_device", params: P(p_blocker: blocker, p_blocked: blocked)).execute()
    }

    func blockedList(blocker: String) async throws -> [BlockedRow] {
        guard let client else { throw BackendError.notConfigured }
        struct P: Encodable { let p_blocker: String }
        return try await client.rpc("blocked_devices", params: P(p_blocker: blocker)).execute().value
    }

    /// There is no account, but there is a devices row, and it has to be
    /// erasable from inside the app.
    func deleteMyData(deviceID: String) async throws {
        guard let client else { throw BackendError.notConfigured }
        struct P: Encodable { let p_device_id: String }
        _ = try await client.rpc("delete_device", params: P(p_device_id: deviceID)).execute()
    }

    /// Ghost mode erases stored coordinates rather than merely halting writes.
    /// Stopping writes leaves your last known position on the server forever,
    /// which is exactly what somebody enabling it is trying to prevent.
    func setGhostMode(deviceID: String, ghost: Bool) async throws {
        guard let client else { throw BackendError.notConfigured }
        struct P: Encodable { let p_device_id: String; let p_ghost: Bool }
        _ = try await client.rpc("set_ghost_mode", params: P(p_device_id: deviceID, p_ghost: ghost)).execute()
    }

    /// Take ownership of a line if nobody holds it.
    ///
    /// The person who opened a session is otherwise load-bearing: they leave,
    /// and the squad still talking behind them has a code that expires under
    /// them. The longest-tenured remaining member is promoted, because they
    /// are the one most likely to still be there in ten minutes.
    func claimHost(squadID: UUID, deviceID: String) async throws -> String? {
        guard let client else { throw BackendError.notConfigured }
        struct P: Encodable { let p_squad_id: String; let p_device_id: String }
        struct R: Decodable { let host: String?
            enum CodingKeys: String, CodingKey { case host = "r_host" } }
        let rows: [R] = try await client
            .rpc("claim_host", params: P(p_squad_id: squadID.uuidString, p_device_id: deviceID))
            .execute().value
        return rows.first?.host
    }

    /// Push the expiry out while a line is genuinely in use, so a code cannot
    /// lapse mid-workout.
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
