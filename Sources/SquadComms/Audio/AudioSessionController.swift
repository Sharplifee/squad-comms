import AVFoundation
import Combine

/// Owns AVAudioSession for the whole app.
///
/// The entire premise is that your music keeps playing and a voice lands on top
/// of it. That only sounds right if two rules hold:
///
/// 1. **The session is configured once and never reconfigured while audio is
///    playing.** Every `setCategory` or `setActive` call while music is running
///    tears down and rebuilds the audio graph, which is audible as a click, a
///    dropout, or a half-second of stutter. The previous implementation called
///    `setCategory` on *every duck and unduck* — so the exact moment your
///    partner spoke was the moment the audio glitched. That is the "tacky dual
///    output" sound, and it was self-inflicted.
///
/// 2. **The session is not activated until a line is actually open, and
///    `.duckOthers` is engaged only while somebody is speaking.** Both of
///    those were wrong before. The session went active at launch and
///    `.duckOthers` was permanent, so simply opening the app pushed your music
///    down and held it there — which is what made it sound like a third-party
///    app playing in the distance instead of your primary audio.
///
/// The v1 failure that killed music outright was `.duckOthers` combined with
/// `.voiceChat` mode. `.voiceChat` forces a telephony signal path — mono, band
/// limited, aggressive AGC — and everything routed through it, including the
/// music, comes out thin. On headphones there is no echo to cancel, so that
/// mode is not needed and is not used.
///
@MainActor
final class AudioSessionController: ObservableObject {

    @Published private(set) var routeName = "Unknown"
    @Published private(set) var usingHeadphones = false

    private let session = AVAudioSession.sharedInstance()
    private var configured = false
    private var currentMode: AVAudioSession.Mode = .default

    // 48 kHz matches what LiveKit's Opus decoder and virtually all music
    // playback already run at. Asking for anything else forces a resampler into
    // the path, which is both latency and a quality loss for no benefit.
    private let preferredSampleRate: Double = 48_000

    // 10 ms. Long enough to survive scheduling jitter when the phone is in a
    // pocket and the CPU is throttled; short enough that voice still feels
    // immediate. 5 ms sounds better on paper and glitches on real devices
    // under load, which is the worst possible trade for this app.
    private let preferredBufferDuration: TimeInterval = 0.010

    // MARK: - Lifecycle

    func configure() throws {
        guard !configured else { return }

        try session.setPreferredSampleRate(preferredSampleRate)
        try session.setPreferredIOBufferDuration(preferredBufferDuration)
        try applyCategory(for: currentRouteIsHeadphones())
        // Deliberately NOT activated here. An active .playAndRecord session
        // holds the microphone and changes the output route, both of which
        // degrade whatever is already playing — for no benefit until there is
        // actually somebody on the line.
        configured = true
        updateRouteState()
        observeRouteChanges()
    }

    /// Re-apply after the noise suppression setting changes. This is the one
    /// case where reconfiguring mid-session is justified, because the user just
    /// asked for it and is listening for the difference.
    func reapplyMode() {
        guard configured else { return }
        try? applyCategory(for: usingHeadphones)
    }

    /// Take the session live. Called when a squad connects, not at launch.
    func activate() throws {
        guard configured else { try configure(); return }
        try session.setActive(true, options: [])
    }

    func deactivate() {
        configured = false
        // .notifyOthersOnDeactivation tells the music app it can return to full
        // volume. Without it, whatever is playing stays ducked after we leave.
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    // MARK: - Category

    /// Mode is chosen by route, and this is the single most important quality
    /// decision in the app.
    ///
    /// On headphones the microphone cannot hear the earpieces, so there is no
    /// echo to cancel, and `.default` keeps the full-bandwidth stereo signal
    /// path intact — music stays music. On the speaker the mic absolutely does
    /// hear the output, so `.voiceChat` and its echo canceller are mandatory or
    /// the squad hears themselves back. We accept the telephony path in that
    /// case because feedback is worse than thin audio, and nobody uses this app
    /// on speaker for long.
    /// Whether the system is currently ducking other apps.
    private(set) var ducking = false

    /// `.duckOthers` must NOT be permanent.
    ///
    /// It ducks the moment our session is active, not the moment we render
    /// audio — so leaving it on meant music was pushed down and back the entire
    /// time the app was open. That is the "sounds like a third-party app in the
    /// distance" problem exactly, and it was self-inflicted.
    ///
    /// `.defaultToSpeaker` is also gone. It forces output to the loudspeaker
    /// even when headphones are attached, which is both wrong and a quality
    /// loss.
    private func baseOptions(ducking: Bool) -> AVAudioSession.CategoryOptions {
        var options: AVAudioSession.CategoryOptions = [
            .mixWithOthers,        // never seize the session from the music app
            .allowBluetooth,
            .allowBluetoothA2DP
        ]
        if ducking { options.insert(.duckOthers) }
        return options
    }

    /// Engage or release the system duck.
    ///
    /// Toggling the category is not free, but it happens only at the edges of
    /// speech — and at those exact moments a voice is either arriving or has
    /// just stopped, which masks the transition. Leaving it on permanently to
    /// avoid the toggle was the far worse trade.
    func setDucking(_ active: Bool) {
        guard configured, ducking != active else { return }
        ducking = active
        try? applyCategory(for: usingHeadphones)
    }

    private func applyCategory(for headphones: Bool) throws {
        // Noise suppression is not a dial iOS exposes — it is a consequence of
        // the session mode, so the setting picks the mode rather than pretending
        // to be a continuous control.
        //
        //   off      → .default      full bandwidth, no processing
        //   standard → .measurement  minimal processing, flat response
        //   active   → .voiceChat    full AGC + noise suppression + AEC
        //
        // On the speaker the choice is overridden: .voiceChat is mandatory
        // there or the mic hears the output and everyone gets feedback.
        let requested: AVAudioSession.Mode
        switch PreferencesStore.shared.current.noiseSuppression {
        case .none:     requested = .default
        case .standard: requested = .measurement
        case .active:   requested = .voiceChat
        }
        let mode: AVAudioSession.Mode = headphones ? requested : .voiceChat
        currentMode = mode

        try session.setCategory(
            .playAndRecord,
            mode: mode,
            options: baseOptions(ducking: ducking)
        )
    }

    // MARK: - Route

    private func currentRouteIsHeadphones() -> Bool {
        session.currentRoute.outputs.contains { output in
            switch output.portType {
            case .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .airPlay, .usbAudio:
                return true
            default:
                return false
            }
        }
    }

    private func updateRouteState() {
        usingHeadphones = currentRouteIsHeadphones()
        routeName = session.currentRoute.outputs.first?.portName ?? "Speaker"
    }

    private func observeRouteChanges() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            Task { @MainActor in self.handleRouteChange(note) }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                // The media daemon died and took every audio object with it.
                // Nothing survives; rebuild from scratch.
                self.configured = false
                try? self.configure()
            }
        }
    }

    private func handleRouteChange(_ note: Notification) {
        let wasHeadphones = usingHeadphones
        updateRouteState()

        // Only reconfigure when the mode actually has to change — pulling one
        // AirPod, or switching between two Bluetooth devices, does not warrant
        // rebuilding the audio graph and the glitch that comes with it.
        guard wasHeadphones != usingHeadphones else { return }

        do {
            try applyCategory(for: usingHeadphones)
            Log.audio.info("audio mode → \(self.usingHeadphones ? "default/headphones" : "voiceChat/speaker", privacy: .public)")
        } catch {
            Log.audio.error("route reconfigure failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
