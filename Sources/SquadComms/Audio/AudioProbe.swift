import AVFoundation

/// What the audio session is ACTUALLY doing, right now.
///
/// The brief carries two fixes written in June that were never confirmed on a
/// device, and they cannot be confirmed remotely — the whole question is what
/// the hardware does. So instead of asking somebody to take it on faith, the
/// app reports its own configuration and lets it be read off the screen.
///
/// This is the difference between "the code says .mixWithOthers" and "the
/// session is currently .playAndRecord/.default with mixWithOthers, 48kHz,
/// routed to AirPods, not ducking" — the second one is evidence.
struct AudioProbe {

    struct Reading {
        let category: String
        let mode: String
        let options: [String]
        let sampleRate: Double
        let bufferMS: Double
        let route: String
        let inputAvailable: Bool
        let otherAudioPlaying: Bool
        let ducking: Bool

        /// The v1 disaster was `.voiceChat` running permanently, which forces
        /// a telephony path and makes music thin. On headphones the mode must
        /// NOT be voiceChat.
        var healthy: Bool {
            options.contains("mixWithOthers")
            && sampleRate >= 44_100
            && !(mode == "VoiceChat" && route.lowercased().contains("airpods"))
        }

        var verdict: String {
            if !options.contains("mixWithOthers") {
                return "Not mixing — your music will be interrupted."
            }
            if mode == "VoiceChat" && route.lowercased().contains("airpods") {
                return "Telephony mode on headphones — music will sound thin."
            }
            if sampleRate < 44_100 {
                return "Low sample rate — audio quality is degraded."
            }
            return "Mixing cleanly at \(Int(sampleRate / 1000)) kHz."
        }
    }

    static func read() -> Reading {
        let session = AVAudioSession.sharedInstance()
        let options = session.categoryOptions

        var names: [String] = []
        if options.contains(.mixWithOthers)      { names.append("mixWithOthers") }
        if options.contains(.duckOthers)         { names.append("duckOthers") }
        if options.contains(.allowBluetooth)     { names.append("allowBluetooth") }
        if options.contains(.allowBluetoothA2DP) { names.append("allowBluetoothA2DP") }
        if options.contains(.defaultToSpeaker)   { names.append("defaultToSpeaker") }

        return Reading(
            category: session.category.rawValue
                .replacingOccurrences(of: "AVAudioSessionCategory", with: ""),
            mode: session.mode.rawValue
                .replacingOccurrences(of: "AVAudioSessionMode", with: ""),
            options: names,
            sampleRate: session.sampleRate,
            bufferMS: session.ioBufferDuration * 1000,
            route: session.currentRoute.outputs.first?.portName ?? "None",
            inputAvailable: session.isInputAvailable,
            otherAudioPlaying: session.isOtherAudioPlaying,
            ducking: options.contains(.duckOthers)
        )
    }
}
