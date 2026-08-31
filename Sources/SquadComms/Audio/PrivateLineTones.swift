import AVFoundation
import Foundation

/// Earcons for the private line.
///
/// A direct line has to be unmistakable the instant it opens. If a private
/// message sounds identical to the squad channel you will answer the wrong
/// person in front of the wrong people, and once that happens once nobody
/// trusts the feature again. So each end of a private line gets its own short
/// tone, distinct from anything the group channel produces.
///
/// Tones are synthesised rather than shipped as assets: three sine bursts cost
/// nothing, always play at the right sample rate, and cannot go missing from a
/// bundle.
enum PrivateLineTones {

    /// Rising two-note pair. Someone has opened a direct line TO you.
    static func incoming() { play(frequencies: [660, 990], duration: 0.09) }

    /// Falling pair, quieter. Your own direct line has opened.
    static func outgoing() { play(frequencies: [880, 660], duration: 0.07, gain: 0.22) }

    /// Single soft note. The private line has closed and you are back on the squad.
    static func closed() { play(frequencies: [520], duration: 0.10, gain: 0.18) }

    // MARK: - Synthesis

    private static let engine = AVAudioEngine()
    private static let player = AVAudioPlayerNode()
    private static var started = false

    private static func play(frequencies: [Double], duration: Double, gain: Float = 0.30) {
        guard let buffer = makeBuffer(frequencies: frequencies, duration: duration, gain: gain)
        else { return }

        if !started {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
            // A tone that fails to start must never take the audio session with
            // it — the squad channel matters more than the earcon.
            try? engine.start()
            started = engine.isRunning
            guard started else { return }
        }

        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    private static func makeBuffer(frequencies: [Double],
                                   duration: Double,
                                   gain: Float) -> AVAudioPCMBuffer? {
        let rate = 44_100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)
        else { return nil }

        let perNote = Int(rate * duration)
        let total   = AVAudioFrameCount(perNote * frequencies.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: total),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = total

        var index = 0
        for frequency in frequencies {
            for sample in 0..<perNote {
                let t = Double(sample) / rate
                // Short attack and release so the tone does not click.
                let progress = Float(sample) / Float(perNote)
                let envelope = min(progress * 12, min((1 - progress) * 12, 1))
                channel[index] = Float(sin(2 * .pi * frequency * t)) * gain * envelope
                index += 1
            }
        }
        return buffer
    }
}
