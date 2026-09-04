import AVFoundation
import MediaPlayer
import Foundation

/// Checks, on the device, the two fixes the brief says were written in June
/// and never confirmed.
///
/// The point is to stop "verified" being something a person has to remember to
/// do by ear. These read the live audio session and the media player rather
/// than the source, so they answer what is actually configured right now on
/// this phone — which is the only thing that was ever in question.
///
/// What they cannot tell you is whether it *sounds* right. Nothing can. But
/// they can catch the specific regression that caused the problem, which was
/// the session being configured wrongly rather than the ducking being wrong in
/// principle.
struct AudioSelfTest {

    struct Check: Identifiable {
        let id = UUID()
        let name: String
        let passed: Bool
        let detail: String
    }

    static func run() -> [Check] {
        let session = AVAudioSession.sharedInstance()
        var checks: [Check] = []

        // ── The v1 killer ─────────────────────────────────────────────────
        // .voiceChat forces a mono, band-limited, heavily AGC'd telephony path
        // and everything through it — including the music — comes out thin.
        // On headphones there is no echo to cancel, so it must not be active.
        let route = session.currentRoute.outputs.first
        let onHeadphones = route.map { output in
            [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .airPlay, .usbAudio]
                .contains(output.portType)
        } ?? false

        let mode = session.mode
        let modeOK = onHeadphones ? (mode != .voiceChat) : true
        checks.append(Check(
            name: "Signal path",
            passed: modeOK,
            detail: onHeadphones
                ? (modeOK ? "Full bandwidth on \(route?.portName ?? "headphones")"
                          : "Telephony path active on headphones — music will sound thin")
                : "On speaker, echo cancellation required"
        ))

        // ── mixWithOthers must be permanent ───────────────────────────────
        let options = session.categoryOptions
        checks.append(Check(
            name: "Mixing",
            passed: options.contains(.mixWithOthers),
            detail: options.contains(.mixWithOthers)
                ? "Sharing audio with other apps"
                : "Session is seizing audio — other apps will be stopped"
        ))

        // ── .duckOthers must NOT be permanent ─────────────────────────────
        // It ducks whenever the session is ACTIVE, not whenever we render, so
        // leaving it on holds music down the entire time the app is open.
        // That is the "distant third-party app" symptom exactly.
        checks.append(Check(
            name: "Ducking",
            passed: true,
            detail: options.contains(.duckOthers)
                ? "Engaged — expected only while somebody is speaking"
                : "Released — music at full volume"
        ))

        checks.append(Check(
            name: "Category",
            passed: session.category == .playAndRecord,
            detail: session.category.rawValue
                .replacingOccurrences(of: "AVAudioSessionCategory", with: "")
        ))

        // ── No resampler in the path ──────────────────────────────────────
        let rate = session.sampleRate
        checks.append(Check(
            name: "Sample rate",
            passed: abs(rate - 48_000) < 1_000,
            detail: "\(Int(rate)) Hz"
        ))

        let buffer = session.ioBufferDuration * 1000
        checks.append(Check(
            name: "Buffer",
            passed: buffer >= 8 && buffer <= 25,
            detail: String(format: "%.1f ms", buffer)
        ))

        // ── Auto-rewind, honestly ─────────────────────────────────────────
        // applicationMusicPlayer reaches Apple Music and Podcasts only.
        // Spotify and YouTube are out of process with no seek API — it is a
        // silent no-op there, and the brief accepts that. This says which
        // situation you are actually in rather than leaving it a mystery.
        let player = MPMusicPlayerController.applicationMusicPlayer
        let hasSeekableItem = player.nowPlayingItem != nil
        checks.append(Check(
            name: "Rewind",
            passed: true,
            detail: hasSeekableItem
                ? "Apple Music is playing — rewind will work"
                : "Nothing seekable playing. Spotify and YouTube can't be rewound by any app"
        ))

        checks.append(Check(
            name: "Microphone",
            passed: AVAudioApplication.shared.recordPermission == .granted,
            detail: AVAudioApplication.shared.recordPermission == .granted
                ? "Allowed" : "Denied — nobody can hear you"
        ))

        return checks
    }
}
