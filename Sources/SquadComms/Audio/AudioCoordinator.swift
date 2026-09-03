import AVFoundation
import Combine

/// Ties VAD, ducking and the LiveKit room together.
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
    private let selfMonitor = SelfMonitor()
    /// Scheduled when a partner starts talking; fires only if they are still
    /// talking N seconds later, which is the difference between a comment and
    /// a conversation.
    private var autoPauseWork: DispatchWorkItem?
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

    }

    func attach(session: SessionManager) {
        self.session = session
        session.onRemoteSpeech = { [weak self] speaking in
            guard let self else { return }
            let prefs = PreferencesStore.shared.current
            // The three-way music choice drives the existing duck machinery.
            let behavior: DuckBehavior
            switch prefs.musicBehaviour {
            case .turnDown:       behavior = .duck
            case .pauseAndRewind: behavior = .rewind
            case .leaveAlone:     behavior = .duck   // nothing engages below
            }
            let ducks = prefs.musicBehaviour != .leaveAlone
            if speaking {
                // Engage the system duck only while they are actually talking.
                self.audioSession.setDucking(ducks && behavior == .duck)
                if ducks { self.ducking.beginDuck(behavior: behavior, level: prefs.duckLevel) }
                // Foldback steps back while someone else has the floor,
                // otherwise you are listening to yourself and them at once.
                self.selfMonitor.setSuppressed(true)
                self.scheduleAutoPause(prefs)
            } else {
                self.autoPauseWork?.cancel()
                self.autoPauseWork = nil
                self.audioSession.setDucking(false)
                if ducks {
                    self.ducking.endDuck(behavior: behavior,
                                         rewindSeconds: behavior == .rewind ? prefs.rewindSeconds : 0)
                }
                self.selfMonitor.setSuppressed(false)
            }
        }
    }

    /// Ducking is right for a passing comment. A conversation that runs past
    /// the threshold is not something you want playing underneath, so the
    /// music stops entirely — but only once it is clearly a conversation.
    private func scheduleAutoPause(_ prefs: Preferences) {
        autoPauseWork?.cancel()
        guard prefs.autoPause, prefs.duckBehavior == .duck else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Log.audio.info("auto-pause: speech ran past threshold, stopping media")
            self.ducking.beginDuck(behavior: .pause, level: 0)
        }
        autoPauseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + prefs.autoPauseSeconds, execute: work)
    }

    /// Live foldback level from the Audio tab; no restart required.
    func setSelfMonitorLevel(_ level: Double) {
        selfMonitor.level = Float(level)
    }

    func startListening() async {
        Log.audio.info("startListening: requesting mic permission")
        micPermissionGranted = await requestMic()
        Log.audio.info("mic permission granted=\(self.micPermissionGranted, privacy: .public)")
        guard micPermissionGranted else {
            Log.audio.error("startListening aborted: microphone denied — no VAD, no transmission")
            return
        }
        do {
            // Session is configured once here and never touched again while
            // audio is playing — see AudioSessionController.
            try audioSession.configure()
            // Now there is a reason to hold the session: a line is open.
            try audioSession.activate()
            try vad.start()

            // Foldback: hear a little of yourself so you do not shout. Failing
            // to start it must never take the voice channel down — it is a
            // comfort feature, not the product.
            selfMonitor.level = Float(PreferencesStore.shared.current.selfMonitor)
            try? selfMonitor.start()
        } catch {
            Log.audio.error("audio start FAILED: \(error.localizedDescription, privacy: .public)")
            Telemetry.event("audio_start_failed", ["error": error.localizedDescription])
        }
    }

    func stopListening() {
        Log.audio.info("stopListening")
        vad.stop()
    }

    func pushToTalkDown() { vad.manualBegin() }
    func pushToTalkUp()   { vad.manualEnd() }

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
                    self.vad.stop()
                    self.selfMonitor.stop()
                    self.ducking.yieldForInterruption()
                case .ended:
                    Log.audio.info("interruption ENDED — restarting VAD")
                    self.ducking.resumeAfterInterruption()
                    do {
                        try self.vad.start()
                        // Previously only VAD came back. CommandEngine was
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
