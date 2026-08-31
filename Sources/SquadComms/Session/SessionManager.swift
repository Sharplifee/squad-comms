import Foundation
import Combine
import LiveKit

/// Owns squad membership, the LiveKit room, and presence.
@MainActor
final class SessionManager: ObservableObject {

    enum DataEvent: String, Codable { case speechStart, speechEnd }

    @Published private(set) var state: SessionState = .idle
    @Published private(set) var squad: Squad?
    @Published private(set) var members: [Member] = []
    @Published private(set) var selfMuted = false

    var onRemoteSpeech: ((Bool) -> Void)?

    private let room = Room()
    private let backend = Backend()
    /// Exposed so the radar can read live distances and drive the range control.
    let proximity = ProximityEngine()
    private var proximityCancellable: AnyCancellable?
    private var speakingRemotes = Set<UUID>()

    init() {
        room.add(delegate: self)
        // ProximityEngine publishes its own contact list. SessionManager is
        // what the view observes, so its objectWillChange must fire too or the
        // radar renders once and then freezes.
        proximityCancellable = proximity.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

        proximity.onNearbyChanged = { [weak self] ids in
            guard let self else { return }
            for index in self.members.indices {
                self.members[index].nearby = ids.contains(self.members[index].id)
            }
        }
    }

    // MARK: - Lifecycle

    func restoreLastSession() async {
        guard let code = UserDefaults.standard.string(forKey: "squadcomms.lastCode") else { return }
        await join(code: code)
    }

    func create(name: String) async {
        state = .connecting
        do {
            let squad = try await backend.createSquad(name: name)
            try await connect(to: squad)
        } catch {
            state = .failed(friendly(error))
        }
    }

    func join(code: String) async {
        state = .connecting
        do {
            let squad = try await backend.squad(forCode: code)
            try await connect(to: squad)
        } catch {
            state = .failed(friendly(error))
        }
    }

    func leave() async {
        await room.disconnect()
        proximity.stop()
        UserDefaults.standard.removeObject(forKey: "squadcomms.lastCode")
        squad = nil
        members = []
        state = .idle
    }

    func reset() { state = .idle }

    /// Open the line without asking anything.
    ///
    /// A code screen on an always-on audio app is a contradiction: it puts a
    /// lock in front of the one thing the app promises. So on launch we
    /// rejoin the last squad silently, and if there has never been one we
    /// create it rather than presenting an empty six-digit field to someone
    /// who has nothing to type into it. The code still exists — it is how you
    /// bring somebody else in — it just is not a gate any more.
    func openLine() async {
        guard case .idle = state else { return }

        if let code = UserDefaults.standard.string(forKey: "squadcomms.lastCode"), !code.isEmpty {
            await join(code: code)
            // A stale or deleted squad must not strand you on a failure screen
            // at launch. Fall through and make a fresh one instead.
            if case .failed = state {
                state = .idle
                await createWithRetry()
            }
            return
        }

        await createWithRetry()
    }

    /// Transient backend trouble at launch must not end in a dead-end screen.
    /// The app's whole promise is that it is already on when you open it, so a
    /// single failed request retries quietly before anything is shown.
    private func createWithRetry() async {
        for delay in [0.0, 1.5, 4.0] {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                state = .idle
            }
            await create(name: defaultSquadName)
            if case .connected = state { return }
        }
    }

    private var defaultSquadName: String {
        let me = PreferencesStore.shared.current.displayName
        return me.isEmpty ? "My squad" : "\(me)'s squad"
    }

    private func connect(to squad: Squad) async throws {
        let token = try await backend.token(for: squad.id,
                                            displayName: PreferencesStore.shared.current.displayName)
        try await room.connect(url: Config.liveKitURL, token: token)
        try await room.localParticipant.setMicrophone(enabled: false)

        self.squad = squad
        UserDefaults.standard.set(squad.joinCode, forKey: "squadcomms.lastCode")
        proximity.start(squadID: squad.id)
        state = .connected
        Telemetry.event("session_connected", ["squad": squad.id.uuidString])
    }

    // MARK: - Controls

    func setMicrophone(enabled: Bool) {
        guard !selfMuted else { return }
        Task { try? await room.localParticipant.setMicrophone(enabled: enabled) }
    }

    func setSelfMuted(_ muted: Bool) {
        selfMuted = muted
        if muted { Task { try? await room.localParticipant.setMicrophone(enabled: false) } }
    }

    func muteAll(_ muted: Bool) {
        for index in members.indices { members[index].isMutedByMe = muted }
        applyRemoteVolumes()
    }

    func setMuted(_ muted: Bool, for member: Member) {
        guard let index = members.firstIndex(where: { $0.id == member.id }) else { return }
        members[index].isMutedByMe = muted
        applyRemoteVolumes()
    }

    func setVolume(_ volume: Double, for member: Member) {
        guard let index = members.firstIndex(where: { $0.id == member.id }) else { return }
        members[index].volume = volume
        applyRemoteVolumes()
    }

    /// Per-listener volume is applied to LiveKit remote tracks — never by
    /// reconfiguring AVAudioSession. This is the fix for the background
    /// audio quality bug from the original build.
    private func applyRemoteVolumes() {
        for participant in room.remoteParticipants.values {
            guard let id = UUID(uuidString: participant.identity?.stringValue ?? ""),
                  let member = members.first(where: { $0.id == id }) else { continue }
            let gain = member.isMutedByMe ? 0 : member.volume
            for publication in participant.audioTracks {
                (publication.track as? RemoteAudioTrack)?.volume = gain
            }
        }
    }

    func broadcast(_ event: DataEvent) {
        guard let data = try? JSONEncoder().encode(event) else { return }
        Task { try? await room.localParticipant.publish(data: data, options: DataPublishOptions(reliable: false)) }
    }

    private func friendly(_ error: Error) -> String {
        if !Config.isConfigured { return "The app isn't configured yet — LiveKit and Supabase keys are missing." }
        return error.localizedDescription
    }
}

// MARK: - LiveKit

extension SessionManager: RoomDelegate {

    nonisolated func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        Task { @MainActor in
            guard let id = UUID(uuidString: participant.identity?.stringValue ?? "") else { return }
            let name = participant.name?.isEmpty == false ? participant.name! : "Squad member"
            if !members.contains(where: { $0.id == id }) {
                members.append(Member(id: id, displayName: name))
            }
        }
    }

    nonisolated func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        Task { @MainActor in
            guard let id = UUID(uuidString: participant.identity?.stringValue ?? "") else { return }
            members.removeAll { $0.id == id }
            speakingRemotes.remove(id)
            onRemoteSpeech?(!speakingRemotes.isEmpty)
        }
    }

    nonisolated func room(_ room: Room, participant: RemoteParticipant?, didReceiveData data: Data, forTopic topic: String,
                          encryptionType: EncryptionType) {
        Task { @MainActor in
            guard let participant,
                  let id = UUID(uuidString: participant.identity?.stringValue ?? ""),
                  let event = try? JSONDecoder().decode(DataEvent.self, from: data) else { return }

            if let index = members.firstIndex(where: { $0.id == id }) {
                members[index].isSpeaking = (event == .speechStart)
            }

            let wasQuiet = speakingRemotes.isEmpty
            if event == .speechStart { speakingRemotes.insert(id) } else { speakingRemotes.remove(id) }

            // Only duck if this member isn't muted by me.
            let audible = members.first(where: { $0.id == id })?.isMutedByMe == false
            if audible && wasQuiet && !speakingRemotes.isEmpty {
                onRemoteSpeech?(true)
            } else if speakingRemotes.isEmpty {
                onRemoteSpeech?(false)
            }
        }
    }
}
