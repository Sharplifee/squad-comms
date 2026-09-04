import Foundation
import AVFoundation
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
    /// Called when the line closes so the audio layer can release the session.
    var onLeave: (() -> Void)?
    /// Set when somebody else closed the line, so the UI can say so rather
    /// than looking like a disconnection.
    @Published var endedByHost = false
    /// The last thing that went wrong, shown inline where you were working.
    ///
    /// Distinct from `.failed`, which replaces the entire app. Almost nothing
    /// deserves that: "that code is taken" and "that line is full" are facts
    /// you act on from the screen you are already on, not reasons to make the
    /// app unusable until you dismiss them.
    @Published var notice: String?
    /// Blocked device ids, applied on join so a blocked person cannot reach
    /// you by starting a fresh session.
    @Published private(set) var blockedIDs: Set<String> = []
    /// Set when this device opened the current line. Closing it for everybody
    /// is the only thing a creator can do that a participant cannot — there is
    /// no muting, kicking or approving, so there is nothing to hand off if the
    /// creator leaves. The line simply continues.
    @Published private(set) var isCreator = false
    private var heartbeatTask: Task<Void, Never>?

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
    private var heartbeat: Timer?
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
    /// The microphone can be revoked in Settings while the app is running.
    /// iOS does not tell you; the audio simply stops being delivered, which
    /// looks exactly like a network problem from the inside.
    @Published var microphoneRevoked = false

    func recheckMicrophonePermission() {
        let granted = AVAudioApplication.shared.recordPermission == .granted
        if !granted && !microphoneRevoked {
            microphoneRevoked = true
            Log.session.error("microphone permission revoked while running")
        } else if granted {
            microphoneRevoked = false
        }
    }

    func loadBlocks() async {
        let rows = (try? await backend.blockedList(blocker: deviceID)) ?? []
        blockedIDs = Set(rows.map(\.deviceID))
    }

    /// Quietly rejoin the last line, if it is still there.
    ///
    /// This runs at launch, so it must NEVER produce a blocking screen. It
    /// previously called join() directly, which sets .failed on any problem —
    /// so an expired code, a flaky network or a stale saved squad greeted you
    /// with a full-screen error before you had asked for anything. Worse, each
    /// launch counted as a failed attempt, and enough of them locked the owner
    /// out of their own squad.
    ///
    /// Opening the app is not a request to connect. If the old line is gone,
    /// the dashboard is the correct outcome.
    func restoreLastSession() async {
        guard let code = UserDefaults.standard.string(forKey: "squadcomms.lastCode"),
              !code.isEmpty else { return }

        do {
            let result = try await withTimeout(Self.connectTimeout) {
                try await self.backend.joinSquad(code: code, deviceID: self.deviceID)
            }
            guard result.outcome == "ok", let squad = result.squad else {
                // Nothing to rejoin. Land on the dashboard, say nothing.
                state = .idle
                return
            }
            try await connect(to: squad)
        } catch {
            state = .idle
        }
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
                isCreator = result.isCreator ?? false
                try await connect(to: squad)
            case "taken":
                // Somebody is live on that code right now. Dropping the caller
                // into a stranger's open microphone is the one outcome that
                // must never happen silently.
                notice = "That code is already in use. Pick another, or join it instead."
                state = .idle
            case "invalid":
                notice = "Codes are 3 to 8 digits."
                state = .idle
            default:
                notice = "Couldn't open the line. Try again."
                state = .idle
            }
        } catch {
            notice = friendly(error)
            state = .idle
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
                isCreator = result.isCreator ?? false
                try await connect(to: squad)
            case "rate_limited":
                // Never a wall. This exists to slow somebody sweeping the code
                // space, and it has no business being the first thing the
                // owner of a squad sees. Wait it out and retry once, silently.
                let wait = min(result.retryAfter ?? 5, 10)
                try? await Task.sleep(nanoseconds: UInt64(wait) * 1_000_000_000)
                let retry = try await self.backend.joinSquad(code: code, deviceID: self.deviceID)
                if retry.outcome == "ok", let squad = retry.squad {
                    try await connect(to: squad)
                } else {
                    state = .idle
                }
            case "not_found":
                notice = "No line open on that code yet — open it instead?"
                state = .idle
            case "expired":
                notice = "That line has ended."
                state = .idle
            case "full":
                notice = "That line is full."
                state = .idle
            case "invalid":
                notice = "Codes are 3 to 8 digits."
                state = .idle
            default:
                notice = "Couldn't join. Try again."
                state = .idle
            }
        } catch {
            notice = friendly(error)
            state = .idle
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
        notice = nil
        state = .connected
        SavedSquadStore.shared.remember(code: squad.joinCode, name: squad.name,
                                        members: members.map(\.displayName))
        startHeartbeat()
        LineActivityController.shared.start(squadName: squad.name,
                                            code: squad.joinCode,
                                            memberCount: members.count)
        // The lock-screen button runs in this process, so it can just call us.
        MuteBridge.shared.toggle = { [weak self] in
            guard let self else { return }
            self.setSelfMuted(!self.selfMuted)
        }
        Task { _ = try? await backend.claimHost(squadID: squad.id, deviceID: deviceID) }
        Telemetry.event("session_connected", ["squad": squad.id.uuidString])
    }

    // MARK: - Controls

    /// Every 45 seconds, comfortably inside the 2 minute presence window so a
    /// single missed beat does not evict somebody mid-set.
    private func startHeartbeat() {
        heartbeatTask?.cancel()
        guard let id = squad?.id else { return }
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 45_000_000_000)
                guard let self, !Task.isCancelled else { return }
                await self.backend.heartbeat(squadID: id, deviceID: self.deviceID)
            }
        }
    }

    // MARK: - Safety

    /// Stop hearing somebody, without reporting them.
    ///
    /// Different act from reporting: a mic picking up a leaf blower does not
    /// need reporting to anybody, it just needs to stop being audible.
    func block(member: Member) async {
        try? await backend.block(blocker: deviceID, blocked: member.id.uuidString)
        setMuted(true, for: member)
        blockedIDs.insert(member.id.uuidString)
    }

    /// Reporting always blocks as well, because asking "and would you also
    /// like to stop hearing them?" straight after somebody reports abuse is a
    /// bad question.
    func report(member: Member, reason: String, detail: String?) async {
        try? await backend.report(reporter: deviceID, reported: member.id.uuidString,
                                  squadID: squad?.id, reason: reason, detail: detail)
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

    // MARK: - Controls

    /// Step out on your own. The line stays open for everyone else.
    func leave() async {
        heartbeatTask?.cancel(); heartbeatTask = nil
        // Release the seat immediately. The last person out also closes the
        // line, so its code is freed rather than reserved for twelve hours
        // after everyone has gone.
        if let id = squad?.id { await backend.leaveSquad(squadID: id, deviceID: deviceID) }
        await room.disconnect()
        proximity.stop()
        LineActivityController.shared.end()
        members.removeAll()
        speakingRemotes.removeAll()
        squad = nil
        sessionStart = nil
        state = .idle
        isCreator = false
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
        if let id = squad?.id {
            try? await backend.endSquad(id: id, deviceID: deviceID)
        }
        await leave()
    }

    private func handleSessionEnded() async {
        endedByHost = true
        await leave()
    }

    func reset() { state = .idle }

    /// Rejoin the same line after a drop LiveKit cannot recover from.
    func reconnectIfNeeded() async {
        guard let squad else { return }
        await room.disconnect()
        state = .connecting
        do { try await connect(to: squad) }
        catch { state = .failed(friendly(error)) }
    }

    /// Keep the lock screen honest about who is talking.
    private func refreshActivity() {
        guard let start = sessionStart else { return }
        LineActivityController.shared.update(
            speaker: members.first(where: { $0.isSpeaking && !$0.isMutedByMe })?.displayName,
            selfMuted: selfMuted,
            memberCount: members.count,
            startedAt: start
        )
    }

    func setMicrophone(enabled: Bool) {
        guard !selfMuted else { return }
        Task { try? await room.localParticipant.setMicrophone(enabled: enabled) }
    }

    func setSelfMuted(_ muted: Bool) {
        selfMuted = muted
        if muted { Task { try? await room.localParticipant.setMicrophone(enabled: false) } }
        refreshActivity()
    }

    /// Re-apply preference-driven audio values after the Audio tab changes
    /// them. Without this the sliders move and nothing happens until the next
    /// reconnect.
    /// Ghost mode stops us advertising over Bluetooth, so nobody sees us on
    /// their radar. It does not affect audio — you can still be heard, which is
    /// the distinction people expect and the reason it is not called "hide".
    func applyPresence() {
        let prefs = PreferencesStore.shared.current
        // Hidden erases the stored position server-side rather than only
        // stopping new writes — otherwise your last known location sits there
        // indefinitely, which is the opposite of what was asked for.
        let invisible = prefs.visibility != .visible
        Task { try? await backend.setGhostMode(deviceID: deviceID,
                                               ghost: prefs.visibility == .hidden) }
        if invisible {
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
                if let squad {
                    SavedSquadStore.shared.remember(code: squad.joinCode, name: squad.name,
                                                    members: members.map(\.displayName))
                }
                // The phone is in a pocket, so a haptic and anything visual
                // both miss entirely.
                PrivateLineTones.joined()
                // The lock screen shows a member count. Without this it shows
                // whatever the count was when the line opened, for the whole
                // session — a stale readout is worse than none, because you
                // trust it.
                refreshActivity()
            }
        }
    }

    nonisolated func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        Task { @MainActor in
            guard let id = UUID(uuidString: participant.identity?.stringValue ?? "") else { return }
            members.removeAll { $0.id == id }
            PrivateLineTones.left()
            refreshActivity()
            speakingRemotes.remove(id)
            onRemoteSpeech?(!speakingRemotes.isEmpty)

            // A private line whose other end just vanished would otherwise
            // leave the whole squad ducked to 12% with nobody to talk to.
            if privateLineTo?.id == id || privateLineFrom?.id == id {
                privateLineTo = nil
                privateLineFrom = nil
                applyRemoteVolumes()
            }

            // Host handoff. Nobody owns the room in LiveKit terms, but the
            // squad row has a creator, and if that person leaves the code
            // would expire on their schedule rather than the group's. The
            // longest-present member takes it over so the line survives the
            // person who opened it walking out.
            if members.isEmpty {
                // Last one out. Keep the line alive rather than closing it —
                // somebody stepping outside for two minutes should not end
                // the session for the person still lifting.
                Log.session.info("last remote left; line held open")
            }
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
                refreshActivity()
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
