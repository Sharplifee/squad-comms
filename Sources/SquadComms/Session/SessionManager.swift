import Foundation
import Combine
import LiveKit

/// Owns squad membership, the LiveKit room, and presence.
@MainActor
final class SessionManager: ObservableObject {

    /// Wire events between squad members. Private-line events carry the
    /// intended recipient, because a direct line is only private if the other
    /// devices can tell it was not addressed to them.
    enum DataEvent: Codable, Equatable {
        case speechStart
        case speechEnd
        case privateLineOpened(to: UUID)
        case privateLineClosed(to: UUID)
        /// Sender is telling one recipient to stop rendering their audio.
        /// Enforced on the receiving side because LiveKit publishes one track
        /// to the room — there is no per-listener mute at the source.
        case routing(to: UUID, muted: Bool)
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

    func restoreLastSession() async {
        guard let code = UserDefaults.standard.string(forKey: "squadcomms.lastCode") else { return }
        await join(code: code)
    }

    func create(name: String, code: String) async {
        state = .connecting
        do {
            let squad = try await backend.joinOrCreateSquad(code: code, name: name)
            self.squad = squad
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

    /// Tear the room down and rejoin the same squad.
    ///
    /// LiveKit reconnects on its own for ordinary drops, but it cannot recover
    /// from a session whose token has expired or whose room was closed
    /// server-side — those look identical from the app and leave you connected
    /// to nothing. This is the manual escape hatch behind Status.
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

        guard let code = UserDefaults.standard.string(forKey: "squadcomms.lastCode"),
              !code.isEmpty else {
            // No code yet. The person picks one during onboarding rather than
            // being handed a generated squad they never asked for.
            state = .needsCode
            return
        }

        await joinOrCreate(code: code)
    }

    /// Join the squad on this code, or create it if nobody has yet.
    ///
    /// The code IS the squad. Two people who agree on "742" both end up in the
    /// same room regardless of who opened the app first, which is the whole
    /// point of letting people choose it — you can say it out loud instead of
    /// reading six digits off a screen.
    /// The code IS the squad. Whoever opens it first creates it, everyone
    /// after joins, and the server resolves the race — so there is no host, no
    /// invite to accept, and no order anyone has to do things in.
    func joinOrCreate(code: String) async {
        UserDefaults.standard.set(code, forKey: "squadcomms.lastCode")
        await createWithRetry(code: code)
    }

    private func createWithRetry(code: String) async {
        for delay in [0.0, 1.5, 4.0] {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                state = .idle
            }
            await create(name: defaultSquadName, code: code)
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
        case .speechStart, .speechEnd:               mustArrive = false
        }
        Task {
            try? await room.localParticipant.publish(
                data: data,
                options: DataPublishOptions(reliable: mustArrive))
        }
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
