import AVFoundation
import Combine

/// Ties VAD, ducking, voice commands and the LiveKit room together.
/// Everything audio-shaped goes through here so there is exactly one owner.
@MainActor
final class AudioCoordinator: ObservableObject {

    @Published private(set) var isTransmitting = false
    @Published private(set) var inputLevelDB: Float = -60
    @Published private(set) var micPermissionGranted = false

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

        commands.onCommand = { [weak self] command in
            self?.handle(command)
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

    private func handle(_ command: CommandEngine.Command) {
        switch command {
        case .muteAll:   session?.muteAll(true)
        case .unmuteAll: session?.muteAll(false)
        case .muteMe:    session?.setSelfMuted(true)
        case .unmuteMe:  session?.setSelfMuted(false)
        case .rewind:
            let prefs = PreferencesStore.shared.current
            ducking.endDuck(behavior: .rewind, rewindSeconds: prefs.rewindSeconds)
        case .leave:
            Task { await session?.leave() }
        }
        Telemetry.event("voice_command", ["command": command.rawValue])
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
