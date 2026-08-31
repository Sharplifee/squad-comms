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
    let audioSession = AudioSessionController()
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
        Log.audio.info("startListening: requesting mic permission")
        micPermissionGranted = await requestMic()
        Log.audio.info("mic permission granted=\(self.micPermissionGranted, privacy: .public)")
        guard micPermissionGranted else {
            Log.audio.error("startListening aborted: microphone denied — no VAD, no commands, no transmission")
            return
        }
        do {
            // Session is configured once here and never touched again while
            // audio is playing — see AudioSessionController.
            try audioSession.configure()
            // Buffers must be forwarded BEFORE the engine starts, or the first
            // utterance after launch is dropped.
            vad.onBuffer = { [weak self] buffer in
                self?.commands.append(buffer)
            }
            try vad.start()

            // Voice commands were previously never started and never fed —
            // CommandEngine.start(on:) had no caller and the recognition
            // request received no audio, so every spoken command was silently
            // dead. Start it on the engine VAD already owns.
            commands.requestAuthorization { [weak self] granted in
                guard let self else { return }
                guard granted else {
                    Log.commands.error("speech recognition NOT authorized — voice commands are off for this install")
                    return
                }
                self.commands.start(on: self.vad.engine)
            }
        } catch {
            Log.audio.error("audio start FAILED: \(error.localizedDescription, privacy: .public)")
            Telemetry.event("audio_start_failed", ["error": error.localizedDescription])
        }
    }

    func stopListening() {
        Log.audio.info("stopListening")
        vad.stop()
        commands.stop()
    }

    func pushToTalkDown() { vad.manualBegin() }
    func pushToTalkUp()   { vad.manualEnd() }

    private func handle(_ intent: VoiceIntent) {
        Log.commands.info("DISPATCH action=\(intent.action.rawValue, privacy: .public) source=\(intent.source.rawValue, privacy: .public) volume=\(intent.volume ?? -1, privacy: .public) members=\(self.session?.members.count ?? 0, privacy: .public)")
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
                    Log.audio.info("interruption BEGAN — yielding audio")
                    self.session?.setMicrophone(enabled: false)
                    self.session?.broadcast(.speechEnd)
                    // Stop commands too. Cancelling the recognition task is the
                    // only way to release its hold on the input; leaving it
                    // running across an interruption is what made every
                    // restart-after-a-phone-call silently fail.
                    self.commands.stop()
                    self.vad.stop()
                    self.ducking.yieldForInterruption()
                case .ended:
                    Log.audio.info("interruption ENDED — restarting VAD and commands")
                    self.ducking.resumeAfterInterruption()
                    do {
                        try self.vad.start()
                        // Previously only VAD came back. CommandEngine was
                        // never restarted, so voice commands were dead after
                        // any phone call until the app was relaunched.
                        self.commands.start(on: self.vad.engine)
                    } catch {
                        Log.audio.error("VAD restart after interruption FAILED: \(error.localizedDescription, privacy: .public)")
                    }
                @unknown default:
                    break
                }
            }
        }
    }
}
