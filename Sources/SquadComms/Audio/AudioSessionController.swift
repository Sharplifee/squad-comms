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
/// 2. **`.duckOthers` is set from the start, not toggled.** It is the only
///    mechanism iOS provides to lower another app's volume, and it is
///    implemented below the app layer in the audio HAL — the ramp is smooth and
///    sample-accurate. Critically it only engages while we are actually
///    rendering audio, which is precisely when somebody is speaking. So leaving
///    it on permanently produces exactly the behaviour we want with zero
///    runtime reconfiguration.
///
/// The v1 failure that killed music was `.duckOthers` combined with
/// `.voiceChat` mode. `.voiceChat` forces a telephony signal path — mono, band
/// limited, aggressive AGC — and everything routed through it, including the
/// music, comes out thin and compressed. That mode is the problem, not the
/// ducking.
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
        try session.setActive(true, options: [])

        configured = true
        updateRouteState()
        observeRouteChanges()
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
    private func applyCategory(for headphones: Bool) throws {
        let mode: AVAudioSession.Mode = headphones ? .default : .voiceChat
        currentMode = mode

        try session.setCategory(
            .playAndRecord,
            mode: mode,
            options: [
                .mixWithOthers,      // never seize the session from the music app
                .duckOthers,         // the only real ducking mechanism iOS offers
                .allowBluetooth,
                .allowBluetoothA2DP,
                .defaultToSpeaker
            ]
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
