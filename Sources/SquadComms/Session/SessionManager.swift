import Foundation
import UIKit
import Combine
import LiveKit

/// Owns squad membership, the LiveKit room, and presence.
@MainActor
final class SessionManager: ObservableObject {

    /// Wire events between squad members. Private-line events carry the
    /// intended recipient, because a direct line is only private if the other
    /// devices can tell it was not addressed to them.
    enum SessionError: LocalizedError {
        case timedOut
        case offline

        var errorDescription: String? {
            switch self {
            // Deliberately different copy: one means try again, the other
            // means fix your connection first. Showing the same message for
            // both sends people to the wrong fix.
            case .timedOut: return "The server didn't answer. Try again."
            case .offline:  return "You're offline. Check your connection."
            }
        }
    }

    enum DataEvent: Codable, Equatable {
        case speechStart
        case speechEnd
        case privateLineOpened(to: UUID)
        case privateLineClosed(to: UUID)
        /// Sender is telling one recipient to stop rendering their audio.
        /// Enforced on the receiving side because LiveKit publishes one track
        /// to the room — there is no per-listener mute at the source.
        case routing(to: UUID, muted: Bool)
        /// The line is being closed for everybody, not just the sender.
        case sessionEnded
    }

    @Published private(set) var state: SessionState = .idle
    @Published private(set) var squad: Squad?
    @Published private(set) var members: [Member] = []

    /// Whoever you currently hold a direct line to. While this is set your
    /// voice reaches only that person, and everyone else in the squad is
    /// ducked hard so the private exchange stays legible.
    @Published private(set) var privateLineTo: Member?
    /// Somebody has opened a direct line to you.
    @Published private(set) var privateLineFrom: Member?
    @Published private(set) var selfMuted = false
    /// When the current session began, for the diagnostics readout.
    @Published private(set) var sessionStart: Date?
    /// Set when somebody else closed the line, so the UI can say so rather
    /// than looking like a disconnection.
    @Published var endedByHost = false
    /// Blocked device ids, applied on join so a blocked person cannot reach
    /// you by starting a fresh session.
    @Published private(set) var blockedIDs: Set<String> = []

    /// Our own LiveKit identity, used to tell whether an inbound private line
    /// was addressed to this device.
    private var selfParticipantID: UUID? {
        UUID(uuidString: room.localParticipant.identity?.stringValue ?? "")
    }

    var onRemoteSpeech: ((Bool) -> Void)?

    private let room = Room()
    /// Exposed so ContactsView can run hash matching through the same client.
    let backend = Backend()
    /// Exposed so the radar can read live distances and drive the range control.
    let proximity = ProximityEngine()
    private var proximityCancellable: AnyCancellable?

    /// One gain envelope per person. Setting a remote track's volume straight
    /// from 0 to 1 the instant VAD fires is a step change in the middle of a
    /// stream — it clicks, and it is the difference between an intercom that
    /// sounds built and one that sounds bolted together.
    private var envelopes: [UUID: VoiceEnvelope] = [:]
    private var envelopeTimer: AnyCancellable?
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

    /// Blocks are loaded before anything connects, so a blocked person is
    /// silent from the first packet rather than after a round trip.
    func loadBlocks() async {
        let rows = (try? await backend.blockedList(blocker: deviceID)) ?? []
        blockedIDs = Set(rows.map(\.deviceID))
    }

    func restoreLastSession() async {
        guard let code = UserDefaults.standard.string(forKey: "squadcomms.lastCode") else { return }
        await join(code: code)
    }

    /// A stable per-install identifier for rate limiting.
    ///
    /// identifierForVendor resets if every app from the vendor is deleted,
    /// which is acceptable — this exists to slow a sweep, not to track anyone.
    private var deviceID: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown-device"
    }

    /// Open a NEW line on a chosen code.
    func create(name: String, code: String) async {
        state = .connecting
        do {
            let result = try await withTimeout(Self.connectTimeout) {
                try await self.backend.createSquad(code: code, name: name, deviceID: self.deviceID)
            }
            switch result.outcome {
            case "ok":
                guard let squad = result.squad else { throw SessionError.timedOut }
                try await connect(to: squad)
            case "taken":
                // Somebody is live on that code right now. Dropping the caller
                // into a stranger's open microphone is the one outcome that
                // must never happen silently.
                state = .failed("That code is already in use. Pick another, or join it instead.")
            case "invalid":
                state = .failed("Codes are 3 to 8 digits.")
            default:
                state = .failed("Couldn't open the line.")
            }
        } catch {
            state = .failed(friendly(error))
        }
    }

    /// Join an EXISTING line. Never creates one.
    func join(code: String) async {
        state = .connecting
        do {
            let result = try await withTimeout(Self.connectTimeout) {
                try await self.backend.joinSquad(code: code, deviceID: self.deviceID)
            }
            switch result.outcome {
            case "ok":
                guard let squad = result.squad else { throw SessionError.timedOut }
                try await connect(to: squad)
            case "rate_limited":
                let wait = result.retryAfter ?? 60
                state = .failed("Too many attempts. Try again in \(wait / 60 > 0 ? "\(wait / 60) min" : "\(wait)s").")
            case "not_found":
                state = .failed("No line open on that code.")
            case "expired":
                state = .failed("That line has ended.")
            case "full":
                state = .failed("That line is full.")
            case "invalid":
                state = .failed("Codes are 3 to 8 digits.")
            default:
                state = .failed("Couldn't join.")
            }
        } catch {
            state = .failed(friendly(error))
        }
    }

    private var defaultSquadName: String {
        let me = PreferencesStore.shared.current.displayName
        return me.isEmpty ? "My squad" : "\(me)'s squad"
    }

    /// Ten seconds, then give up with something the user can act on.
    ///
    /// There was no timeout anywhere, so any backend hang left the app on
    /// "Opening the line" forever with no way out but force-quitting. A
    /// spinner that can never end is worse than an error, because an error at
    /// least tells you to try again.
    private static let connectTimeout: TimeInterval = 10

    private func withTimeout<T>(_ seconds: TimeInterval,
                                _ operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw SessionError.timedOut
            }
            guard let first = try await group.next() else { throw SessionError.timedOut }
            group.cancelAll()
            return first
        }
    }

    private func connect(to squad: Squad) async throws {
        // Every network hop gets a ceiling, not just the LiveKit connect —
        // an Edge Function that never answers stranded the app just as
        // effectively as a room that never joined.
        let token = try await withTimeout(Self.connectTimeout) {
            try await self.backend.token(for: squad.id,
                                         displayName: PreferencesStore.shared.current.displayName)
        }
        try await withTimeout(Self.connectTimeout) {
            try await self.room.connect(url: Config.liveKitURL, token: token)
        }
        try await room.localParticipant.setMicrophone(enabled: false)

        self.squad = squad
        UserDefaults.standard.set(squad.joinCode, forKey: "squadcomms.lastCode")
        // Each device must advertise ITSELF, not the squad, or every peer
        // decodes to the same identity and the radar shows one dot.
        if let me = UUID(uuidString: room.localParticipant.identity?.stringValue ?? "") {
            proximity.start(squadID: squad.id, selfID: me)
        }
        sessionStart = Date()
        state = .connected
        Telemetry.event("session_connected", ["squad": squad.id.uuidString])
    }

    // MARK: - Controls

    /// Step out on your own. The line stays open for everyone else.
    func leave() async {
        await room.disconnect()
        proximity.stop()
        envelopeTimer?.cancel(); envelopeTimer = nil
        envelopes.removeAll()
        members.removeAll()
        speakingRemotes.removeAll()
        squad = nil
        sessionStart = nil
        privateLineTo = nil
        privateLineFrom = nil
        state = .idle
    }

    /// Close the line for everyone in it.
    ///
    /// Distinct from leaving. Walking out of a finished workout and leaving
    /// people connected to an empty room is not what you meant, but neither is
    /// kicking everybody every time you personally need to go.
    func endForEveryone() async {
        broadcast(.sessionEnded)
        // Let the message leave before tearing down the room it travels over.
        try? await Task.sleep(nanoseconds: 250_000_000)
        if let id = squad?.id { try? await backend.endSquad(id: id) }
        await leave()
    }

    private func handleSessionEnded() async {
        endedByHost = true
        await leave()
    }

    func reset() { state = .idle }

    /// Rejoin the same line after a drop LiveKit cannot recover from — an
    /// expired token or a room closed server-side both look identical from
    /// here and leave you connected to nothing.
    func reconnectIfNeeded() async {
        guard let squad else { return }
        await room.disconnect()
        state = .connecting
        do {
            try await connect(to: squad)
        } catch {
            state = .failed(friendly(error))
        }
    }

    // MARK: - Safety

    func report(member: Member, reason: String, detail: String?) async {
        try? await backend.report(reporter: deviceID, reported: member.id.uuidString,
                                  squadID: squad?.id, reason: reason, detail: detail)
        // Take effect immediately rather than waiting for a round trip — the
        // person is still audible while the request is in flight.
        setMuted(true, for: member)
        blockedIDs.insert(member.id.uuidString)
    }

    func block(member: Member) async {
        try? await backend.block(blocker: deviceID, blocked: member.id.uuidString)
        setMuted(true, for: member)
        blockedIDs.insert(member.id.uuidString)
    }

    func unblock(deviceID target: String) async {
        try? await backend.unblock(blocker: deviceID, blocked: target)
        blockedIDs.remove(target)
    }

    func blockedList() async -> [Backend.BlockedRow] {
        (try? await backend.blockedList(blocker: deviceID)) ?? []
    }

    func deleteMyData() async {
        try? await backend.deleteMyData(deviceID: deviceID)
        await leave()
        UserDefaults.standard.removeObject(forKey: "squadcomms.lastCode")
        UserDefaults.standard.removeObject(forKey: "squadcomms.onboarded")
    }

    func setMicrophone(enabled: Bool) {
        guard !selfMuted else { return }
        Task { try? await room.localParticipant.setMicrophone(enabled: enabled) }
    }

    func setSelfMuted(_ muted: Bool) {
        selfMuted = muted
        if muted { Task { try? await room.localParticipant.setMicrophone(enabled: false) } }
    }

    /// Re-apply preference-driven audio values after the Audio tab changes
    /// them. Without this the sliders move and nothing happens until the next
    /// reconnect.
    /// Ghost mode stops us advertising over Bluetooth, so nobody sees us on
    /// their radar. It does not affect audio — you can still be heard, which is
    /// the distinction people expect and the reason it is not called "hide".
    func applyPresence() {
        let prefs = PreferencesStore.shared.current
        // Ghost mode erases the stored position server-side rather than only
        // stopping new writes — otherwise your last known location sits there
        // indefinitely, which is the opposite of what was asked for.
        Task { try? await backend.setGhostMode(deviceID: deviceID, ghost: prefs.ghostMode) }
        if prefs.ghostMode {
            proximity.stopAdvertising()
        } else if let squad, let me = UUID(uuidString: room.localParticipant.identity?.stringValue ?? "") {
            proximity.start(squadID: squad.id, selfID: me)
        }
    }

    func applyPreferences() {
        let prefs = PreferencesStore.shared.current
        for index in members.indices where !members[index].isMutedByMe {
            members[index].volume = prefs.intercomVolume
        }
        applyRemoteVolumes()
    }

    func muteAll(_ muted: Bool) {
        for index in members.indices { members[index].isMutedByMe = muted }
        applyRemoteVolumes()
    }

    /// Stop this person hearing you, without affecting whether you hear them.
    ///
    /// Implemented per-participant rather than by muting the mic, so everyone
    /// else in the squad still hears you normally.
    func setMutedToThem(_ muted: Bool, for member: Member) {
        guard let index = members.firstIndex(where: { $0.id == member.id }) else { return }
        members[index].isMutedToThem = muted
        broadcast(.routing(to: member.id, muted: muted))
    }

    func setMuted(_ muted: Bool, for member: Member) {
        guard let index = members.firstIndex(where: { $0.id == member.id }) else { return }
        members[index].isMutedByMe = muted
        applyRemoteVolumes()
    }

    // MARK: - Private line
    //
    // Hold a name and you are talking only to that person. Release and you are
    // back on the squad. Deliberately momentary rather than a mode you toggle:
    // a private channel you can forget you left open is how you say something
    // to one person that you believed the whole group could hear, or worse.

    func beginPrivateLine(to member: Member) {
        guard privateLineTo?.id != member.id else { return }
        privateLineTo = member
        PrivateLineTones.outgoing()
        Haptics.impact(.rigid)
        broadcast(.privateLineOpened(to: member.id))
        applyRemoteVolumes()
        setMicrophone(enabled: true)
    }

    func endPrivateLine() {
        guard let member = privateLineTo else { return }
        privateLineTo = nil
        PrivateLineTones.closed()
        broadcast(.privateLineClosed(to: member.id))
        applyRemoteVolumes()
        setMicrophone(enabled: false)
    }

    /// Someone opened a direct line to you.
    func receivePrivateLine(from id: UUID) {
        guard let member = members.first(where: { $0.id == id }) else { return }
        privateLineFrom = member
        PrivateLineTones.incoming()
        Haptics.impact(.rigid)
        applyRemoteVolumes()
    }

    func endPrivateLine(from id: UUID) {
        guard privateLineFrom?.id == id else { return }
        privateLineFrom = nil
        PrivateLineTones.closed()
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
    /// Set where each person's voice *should* sit. The envelope walks the
    /// actual gain there over the next few hundred milliseconds.
    private func applyRemoteVolumes() {
        for member in members {
            let envelope = envelopes[member.id] ?? {
                let new = VoiceEnvelope()
                envelopes[member.id] = new
                return new
            }()

            // On a private line the other party is the only thing that should
            // be clearly audible; the rest of the squad drops well down rather
            // than to silence, so you still notice if the room erupts.
            var target = member.isMutedByMe ? 0 : Float(member.volume)
            if let solo = privateLineFrom ?? privateLineTo {
                target = (member.id == solo.id) ? max(target, 0.9) : target * 0.12
            }

            envelope.openLevel = target
            if target > 0 && member.isSpeaking {
                envelope.open()
            } else if target == 0 {
                envelope.open()          // muting is immediate on purpose
                envelope.openLevel = 0
            } else {
                envelope.close()
            }
        }
        startEnvelopeDriver()
    }

    /// Drives every envelope at 60 Hz and pushes the result onto the tracks.
    /// Runs only while there is something still moving, so an idle squad costs
    /// nothing.
    private func startEnvelopeDriver() {
        guard envelopeTimer == nil else { return }
        envelopeTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                var moving = false

                for participant in self.room.remoteParticipants.values {
                    guard let id = UUID(uuidString: participant.identity?.stringValue ?? ""),
                          let envelope = self.envelopes[id] else { continue }
                    let previous = envelope.currentGain
                    let gain = envelope.tick()
                    if abs(gain - previous) > 0.0001 { moving = true }
                    for publication in participant.audioTracks {
                        (publication.track as? RemoteAudioTrack)?.volume = Double(gain)
                    }
                }

                if !moving {
                    self.envelopeTimer?.cancel()
                    self.envelopeTimer = nil
                }
            }
    }

    func broadcast(_ event: DataEvent) {
        guard let data = try? JSONEncoder().encode(event) else { return }
        // Speech start/stop is fine to drop — another one follows in
        // milliseconds. A private-line close is not: if it goes missing the far
        // end stays ducked to 12% permanently with no way to recover, so those
        // go reliably.
        let mustArrive: Bool
        switch event {
        case .privateLineOpened, .privateLineClosed: mustArrive = true
        // Routing is a latch, not a stream — nothing follows it to correct a
        // drop, so a lost message would leave somebody muted or unmuted
        // against their intent with no way to notice.
        case .routing:                               mustArrive = true
        case .sessionEnded:                          mustArrive = true
        case .speechStart, .speechEnd:               mustArrive = false
        }
        Task {
            try? await room.localParticipant.publish(
                data: data,
                options: DataPublishOptions(reliable: mustArrive))
        }
    }

    private func friendly(_ error: Error) -> String {
        // No network and a silent server need different words, because they
        // need different actions from the person reading them.
        if !NetworkReachability.isOnline { return SessionError.offline.errorDescription! }
        if case SessionError.timedOut = error { return SessionError.timedOut.errorDescription! }
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
            // A block has to survive a new session, or blocking somebody just
            // means they rejoin under a fresh code and you are back where you
            // started.
            if blockedIDs.contains(id.uuidString) {
                for publication in participant.audioTracks {
                    (publication.track as? RemoteAudioTrack)?.volume = 0
                }
                return
            }
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

            switch event {
            case .privateLineOpened(let target):
                // Only the addressed device opens the line; everyone else
                // discards it, which is what makes it private.
                if target == selfParticipantID { receivePrivateLine(from: id) }
                return
            case .privateLineClosed(let target):
                if target == selfParticipantID { endPrivateLine(from: id) }
                return
            case .routing(let target, let muted):
                guard target == selfParticipantID else { return }
                if let index = members.firstIndex(where: { $0.id == id }) {
                    // They have muted themselves to us specifically. Drop their
                    // gain rather than showing them as speaking to nobody.
                    members[index].isMutedByMe = muted
                    applyRemoteVolumes()
                }
                return
            case .sessionEnded:
                Task { await handleSessionEnded() }
                return
            case .speechStart, .speechEnd:
                break
            }

            if let index = members.firstIndex(where: { $0.id == id }) {
                members[index].isSpeaking = (event == .speechStart)
                // Speech state is what opens and closes the envelope, so the
                // ramp has to be re-driven the moment it changes.
                applyRemoteVolumes()
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
