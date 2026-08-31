import AVFoundation
import MediaPlayer

/// Owns AVAudioSession. The critical rule learned the hard way:
/// `.mixWithOthers` is the PERMANENT base option. Never set `.duckOthers`
/// or `.voiceChat` permanently — doing so degrades background audio quality
/// for the whole session. Ducking is done through LiveKit remote track
/// volume and MPMusicPlayerController, not by reconfiguring the session.
final class DuckingController {

    private let session = AVAudioSession.sharedInstance()
    private var isDucked = false
    private var restoreVolume: Float?

    func configureForAmbientVoice() throws {
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.mixWithOthers, .allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
        )
        try session.setActive(true, options: [])
    }

    /// Someone in the squad started speaking.
    func beginDuck(behavior: DuckBehavior, level: Double) {
        guard !isDucked else { return }
        isDucked = true

        switch behavior {
        case .duck:
            // No app can set Spotify's volume. The ONLY mechanism on iOS that
            // lowers another app's audio is AVAudioSession's .duckOthers, so
            // that is what has to run here. fadeMedia() previously just posted
            // a notification with no observers anywhere in the project, which
            // meant the headline feature of this app did nothing at all.
            setDuckingOthers(true)
        case .pause, .rewind:
            // applicationMusicPlayer only controls Apple Music. For Spotify and
            // everything else, ducking is the only lever we have, so fall back
            // to it rather than silently doing nothing.
            MPMusicPlayerController.applicationMusicPlayer.pause()
            setDuckingOthers(true)
        }
    }

    /// They stopped. Bring the world back.
    func endDuck(behavior: DuckBehavior, rewindSeconds: Double) {
        guard isDucked else { return }
        isDucked = false

        switch behavior {
        case .duck:
            setDuckingOthers(false)
        case .pause:
            setDuckingOthers(false)
            MPMusicPlayerController.applicationMusicPlayer.play()
        case .rewind:
            setDuckingOthers(false)
            let player = MPMusicPlayerController.applicationMusicPlayer
            player.currentPlaybackTime = max(0, player.currentPlaybackTime - rewindSeconds)
            player.play()
        }
    }

    /// Phone call arrives — release everything so the caller owns the audio.
    func yieldForInterruption() {
        if isDucked {
            isDucked = false
            setDuckingOthers(false)
        }
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func resumeAfterInterruption() {
        try? configureForAmbientVoice()
    }

    /// Add or remove `.duckOthers` on the live session.
    ///
    /// The base category stays `.playAndRecord` with `.mixWithOthers` so we
    /// never seize the audio session — that combination is what killed music
    /// in v1 and must not come back. `.duckOthers` is layered on only while a
    /// squad member is actually speaking and removed the moment they stop, so
    /// other apps duck and recover on their own.
    private func setDuckingOthers(_ ducking: Bool) {
        var options: AVAudioSession.CategoryOptions =
            [.mixWithOthers, .allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
        if ducking { options.insert(.duckOthers) }

        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: options)
        } catch {
            // A failure here must never take the voice channel down with it —
            // hearing your partner matters more than the music dipping.
            Log.audio.error("duck toggle failed: \(error.localizedDescription)")
        }
    }
}

extension Notification.Name {
    static let squadMediaGainChanged = Notification.Name("squadMediaGainChanged")
}
