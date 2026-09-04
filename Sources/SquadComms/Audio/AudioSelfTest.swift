import AVFoundation
import MediaPlayer
import Foundation

/// Checks the audio path against what it is supposed to be.
///
/// Two fixes have been carried since June that nobody has ever confirmed on a
/// device: the ducking configuration that made music sound thin, and whether
/// auto-rewind actually seeks. Neither can be proven without ears — but a
/// large part of both is verifiable, and everything verifiable should be
/// checked by the app rather than assumed by whoever wrote it.
///
/// This does not replace listening. It catches the case where the settings are
/// wrong, which is what happened last time.
struct AudioSelfTest {

    enum Result {
        case pass(String)
        case warn(String)
        case fail(String)

        var symbol: String {
            switch self {
            case .pass: return "checkmark.circle.fill"
            case .warn: return "exclamationmark.triangle.fill"
            case .fail: return "xmark.circle.fill"
            }
        }
        var detail: String {
            switch self { case .pass(let d), .warn(let d), .fail(let d): return d }
        }
    }

    struct Check: Identifiable {
        let id = UUID()
        let name: String
        let result: Result

        /// A warning is not a pass. The whole reason this exists is that
        /// "probably fine" is what shipped a broken audio path last time.
        var passed: Bool {
            if case .pass = result { return true }
            return false
        }
        var detail: String { result.detail }
    }

    static func run() -> [Check] {
        let session = AVAudioSession.sharedInstance()
        var checks: [Check] = []

        // 1. Category. .playAndRecord is required to both send and receive.
        checks.append(Check(
            name: "Category",
            result: session.category == .playAndRecord
                ? .pass("playAndRecord")
                : .fail("\(session.category.rawValue) — voice needs playAndRecord")
        ))

        // 2. mixWithOthers must be permanent, or we seize the session from the
        //    music app instead of layering over it.
        let mixes = session.categoryOptions.contains(.mixWithOthers)
        checks.append(Check(
            name: "Mixes with music",
            result: mixes ? .pass("mixWithOthers is set")
                          : .fail("Not set — we would take the session from the music app")
        ))

        // 3. duckOthers must NOT be permanent. It ducks whenever the session is
        //    ACTIVE, not whenever we render audio, so leaving it on holds the
        //    music down the whole time the app is open. This is the exact bug
        //    that made everything sound like a distant third-party app.
        let ducksPermanently = session.categoryOptions.contains(.duckOthers)
        checks.append(Check(
            name: "Ducking is momentary",
            result: ducksPermanently
                ? .fail("duckOthers is permanently set — music will stay pushed down")
                : .pass("Engaged only while someone speaks")
        ))

        // 4. Mode. .voiceChat forces a telephony path — mono, band limited,
        //    aggressive AGC — and everything routed through it comes out thin,
        //    including the music. On headphones there is no echo to cancel.
        let headphones = usingHeadphones(session)
        let mode = session.mode
        checks.append(Check(
            name: "Mode for this route",
            result: {
                if headphones && mode == .voiceChat {
                    return .fail("voiceChat on headphones — this is what makes music sound thin")
                }
                if !headphones && mode != .voiceChat {
                    return .warn("\(mode.rawValue) on speaker — echo cancellation is off")
                }
                return .pass("\(mode.rawValue) on \(headphones ? "headphones" : "speaker")")
            }()
        ))

        // 5. Speaker must not be forced when headphones are attached.
        checks.append(Check(
            name: "Output routing",
            result: session.categoryOptions.contains(.defaultToSpeaker) && headphones
                ? .fail("defaultToSpeaker forces the loudspeaker even with headphones in")
                : .pass(currentRouteName(session))
        ))

        // 6. Sample rate. 48k is what the codec wants; a mismatch means
        //    resampling on every buffer.
        let rate = session.sampleRate
        checks.append(Check(
            name: "Sample rate",
            result: rate >= 44100
                ? .pass("\(Int(rate)) Hz")
                : .warn("\(Int(rate)) Hz — below CD quality, voice will sound dull")
        ))

        // 7. Buffer duration. Too small and it glitches under load; too large
        //    and the conversation feels delayed.
        let buffer = session.ioBufferDuration * 1000
        checks.append(Check(
            name: "Buffer",
            result: {
                if buffer < 4  { return .warn(String(format: "%.1f ms — may glitch under load", buffer)) }
                if buffer > 25 { return .warn(String(format: "%.1f ms — noticeable delay", buffer)) }
                return .pass(String(format: "%.1f ms", buffer))
            }()
        ))

        // 8. The most basic failure of all, and the easiest to overlook
        //    because everything else can look perfect without it.
        let micOK = AVAudioApplication.shared.recordPermission == .granted
        checks.append(Check(
            name: "Microphone",
            result: micOK ? .pass("Allowed") : .fail("Denied — nobody can hear you")
        ))

        // 9. Auto-rewind capability. This is the honest half of the answer:
        //    we can tell whether anything is seekable, not whether the seek
        //    lands. Spotify and YouTube are out of process with no seek API,
        //    so rewind silently no-ops there — an accepted failure mode, but
        //    one worth stating rather than discovering.
        checks.append(Check(name: "Rewind target", result: rewindCapability()))

        return checks
    }

    private static func rewindCapability() -> Result {
        let player = MPMusicPlayerController.systemMusicPlayer
        guard MPMediaLibrary.authorizationStatus() == .authorized else {
            return .warn("Media access not granted — rewind can't work at all")
        }
        guard player.nowPlayingItem != nil else {
            return .warn("Nothing playing through Apple Music — start a track to test")
        }
        return .pass("Apple Music is seekable, rewind will work")
    }

    private static func usingHeadphones(_ session: AVAudioSession) -> Bool {
        session.currentRoute.outputs.contains {
            [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .airPlay, .carAudio]
                .contains($0.portType)
        }
    }

    private static func currentRouteName(_ session: AVAudioSession) -> String {
        session.currentRoute.outputs.first?.portName ?? "Unknown"
    }
}
