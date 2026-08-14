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
            fadeMedia(to: Float(level), over: 0.18)
        case .pause, .rewind:
            MPMusicPlayerController.applicationMusicPlayer.pause()
        }
    }

    /// They stopped. Bring the world back.
    func endDuck(behavior: DuckBehavior, rewindSeconds: Double) {
        guard isDucked else { return }
        isDucked = false

        switch behavior {
        case .duck:
            fadeMedia(to: 1.0, over: 0.35)
        case .pause:
            MPMusicPlayerController.applicationMusicPlayer.play()
        case .rewind:
            let player = MPMusicPlayerController.applicationMusicPlayer
            player.currentPlaybackTime = max(0, player.currentPlaybackTime - rewindSeconds)
            player.play()
        }
    }

    /// Phone call arrives — release everything so the caller owns the audio.
    func yieldForInterruption() {
        if isDucked {
            isDucked = false
            fadeMedia(to: 1.0, over: 0.1)
        }
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func resumeAfterInterruption() {
        try? configureForAmbientVoice()
    }

    // Volume is applied to LiveKit remote tracks by the room manager; this
    // handles the user's own media layer only.
    private func fadeMedia(to target: Float, over duration: TimeInterval) {
        // Ramp in small steps so it never sounds like a hard cut.
        let steps = 12
        let interval = duration / Double(steps)
        let start = restoreVolume ?? 1.0
        restoreVolume = target == 1.0 ? nil : start

        for i in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(i)) {
                let t = Float(i) / Float(steps)
                let value = start + (target - start) * t
                NotificationCenter.default.post(
                    name: .squadMediaGainChanged, object: nil, userInfo: ["gain": value]
                )
            }
        }
    }
}

extension Notification.Name {
    static let squadMediaGainChanged = Notification.Name("squadMediaGainChanged")
}
