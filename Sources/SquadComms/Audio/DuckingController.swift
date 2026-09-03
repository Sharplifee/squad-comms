import AVFoundation
import MediaPlayer

/// Owns AVAudioSession. The critical rule learned the hard way:
/// `.mixWithOthers` is the PERMANENT base option. Never set `.duckOthers`
/// or `.voiceChat` permanently — doing so degrades background audio quality
/// for the whole session. Ducking is done through LiveKit remote track
/// volume and MPMusicPlayerController, not by reconfiguring the session.
/// Media behaviour when someone speaks.
///
/// Ducking itself is handled by the audio session, which is configured once
/// with `.duckOthers` and then left alone — see AudioSessionController for why
/// touching the session mid-playback is what made the old build glitch. This
/// type only handles the behaviours the system cannot do for us: pausing and
/// rewinding, which apply to Apple Music and Podcasts.
final class DuckingController {

    private var isDucked = false

    /// Someone in the squad started speaking.
    ///
    /// For `.duck` there is deliberately nothing to do. The system is already
    /// ducking because we are rendering audio, and it does it in the audio HAL
    /// with a proper ramp — far better than anything reachable from here.
    func beginDuck(behavior: DuckBehavior, level: Double) {
        guard !isDucked else { return }
        isDucked = true

        switch behavior {
        case .duck, .off:
            break
        case .pause, .rewind:
            // applicationMusicPlayer reaches Apple Music and Podcasts only.
            // Spotify and YouTube expose no transport control to other apps, so
            // for those the system duck is the whole story — which is why the
            // Audio tab says so plainly instead of pretending otherwise.
            MPMusicPlayerController.applicationMusicPlayer.pause()
        }
    }

    /// They stopped. Bring the world back.
    func endDuck(behavior: DuckBehavior, rewindSeconds: Double) {
        guard isDucked else { return }
        isDucked = false

        switch behavior {
        case .duck, .off:
            break
        case .pause:
            MPMusicPlayerController.applicationMusicPlayer.play()
        case .rewind:
            let player = MPMusicPlayerController.applicationMusicPlayer
            player.currentPlaybackTime = max(0, player.currentPlaybackTime - rewindSeconds)
            player.play()
        }
    }

    func reset() {
        isDucked = false
    }

    /// A phone call, Siri or an alarm has taken the audio session.
    ///
    /// Fighting for it is pointless and produces exactly the stuttering
    /// contention this app exists to avoid, so drop any media behaviour we
    /// asked for and let the interruption own the output.
    func yieldForInterruption() {
        isDucked = false
    }

    /// The interruption is over. If the user's setting was pause, their music
    /// was paused by us rather than by the interruption, so it will not come
    /// back on its own and has to be resumed explicitly.
    func resumeAfterInterruption() {
        let prefs = PreferencesStore.shared.current
        if prefs.duckBehavior == .pause || prefs.duckBehavior == .rewind {
            MPMusicPlayerController.applicationMusicPlayer.play()
        }
    }
}

extension Notification.Name {
    static let squadMediaGainChanged = Notification.Name("squadMediaGainChanged")
}
