import AVFoundation
import Combine

/// Ties VAD, ducking, voice commands and the LiveKit room together.
/// Everything audio-shaped goes through here so there is exactly one owner.
@MainActor
final class AudioCoordinator: ObservableObject {

    @Published private(set) var isTransmitting = false
    @Published private(set) var inputLevelDB: Float = -60
    @Published private(set) var micPermissionGranted = false

    /// Set when the squad asks "who's on". The UI reads it and clears it.
    @Published var rosterAnnouncement: String?

    private let vad = VADEngine()
    private let ducking = DuckingController()
    private let commands = CommandEngine()
    private weak var session: SessionManager?
    private var cancellables = Set<AnyCancellable>()

    init() {
        observeInterruptions()

        vad.onTransmissionBegan = { [weak self] in
            guard let self else { return }
            self.isTransmitting = true
            self.session?.setMicrophone(enabled: true)
            self.session?.broadcast(.speechStart)
            Telemetry.event("transmission_began")
        }

        vad.onTransmissionEnded = { [weak self] in
            guard let self else { return }
            self.isTransmitting = false
            self.session?.setMicrophone(enabled: false)
            self.session?.broadcast(.speechEnd)
        }

        vad.$inputLevelDB
            .receive(on: RunLoop.main)
            .assign(to: \.inputLevelDB, on: self)
            .store(in: &cancellables)

        commands.rosterProvider = { [weak self] in
            self?.session?.members.map(\.displayName) ?? []
        }

        commands.onIntent = { [weak self] intent in
            Task { @MainActor in self?.handle(intent) }
        }
    }

    func attach(session: SessionManager) {
        self.session = session
        session.onRemoteSpeech = { [weak self] speaking in
            guard let self else { return }
            let prefs = PreferencesStore.shared.current
            if speaking {
                self.ducking.beginDuck(behavior: prefs.duckBehavior, level: prefs.duckLevel)
            } else {
                self.ducking.endDuck(behavior: prefs.duckBehavior, rewindSeconds: prefs.rewindSeconds)
            }
        }
    }

    func startListening() async {
        micPermissionGranted = await requestMic()
        guard micPermissionGranted else { return }
        commands.requestAuthorization { _ in }
        do {
            try ducking.configureForAmbientVoice()
            try vad.start()
        } catch {
            Telemetry.event("audio_start_failed", ["error": error.localizedDescription])
        }
    }

    func stopListening() {
        vad.stop()
        commands.stop()
    }

    func pushToTalkDown() { vad.manualBegin() }
    func pushToTalkUp()   { vad.manualEnd() }

    private func handle(_ intent: VoiceIntent) {
        switch intent.action {
        case .muteAll:   session?.muteAll(true)
        case .unmuteAll: session?.muteAll(false)
        case .mute:      session?.setSelfMuted(true)
        case .unmute:    session?.setSelfMuted(false)
        case .setVolume:
            guard let volume = intent.volume, let session else { break }
            // "set my volume to X" is about how loud the squad is in this
            // listener's ears, so it applies to every remote track.
            for member in session.members {
                session.setVolume(volume, for: member)
            }
        case .whosOn:
            let names = session?.members.map(\.displayName) ?? []
            rosterAnnouncement = names.isEmpty
                ? "Nobody else is on the line."
                : names.joined(separator: ", ")
        case .rewind:
            let prefs = PreferencesStore.shared.current
            ducking.endDuck(behavior: .rewind, rewindSeconds: prefs.rewindSeconds)
        case .leave:
            Task { await session?.leave() }
        case .unknown:
            return
        }
        Telemetry.event("voice_command", [
            "action": intent.action.rawValue,
            "source": intent.source.rawValue,
            "confidence": String(format: "%.2f", intent.confidence),
        ])
    }

    private func requestMic() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
    }

    /// Incoming phone call: drop out cleanly, tell the squad, come back after.
    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }

            Task { @MainActor in
                switch type {
                case .began:
                    self.session?.setMicrophone(enabled: false)
                    self.session?.broadcast(.speechEnd)
                    self.vad.stop()
                    self.ducking.yieldForInterruption()
                case .ended:
                    self.ducking.resumeAfterInterruption()
                    try? self.vad.start()
                @unknown default:
                    break
                }
            }
        }
    }
}
