import AVFoundation

/// Your own voice, played back into your own ears.
///
/// With sealed earbuds in and music playing you cannot hear yourself properly,
/// so you shout. Everyone on the line then hears a shouted voice on top of
/// their music, and the natural response is to shout back. Broadcast engineers
/// solved this decades ago with foldback: feed a little of the talker's own
/// voice back to them and they instantly settle to a normal level.
///
/// The level is deliberately low. Around 20% is the point where you can hear
/// yourself without it feeling like a delay or an echo — above roughly 40% the
/// round-trip latency becomes audible as a slap and it gets distracting rather
/// than helpful.
final class SelfMonitor {

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let mixer = AVAudioMixerNode()
    private var running = false

    /// 0…1. Applied live; changing it does not restart anything.
    var level: Float = 0.20 {
        didSet { mixer.outputVolume = clamped(level) }
    }

    func start() throws {
        guard !running else { return }

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)

        // A zero sample rate means the route is mid-change or the session is
        // not active yet. Starting here throws an uncatchable Obj-C exception,
        // so bail and let the caller retry after the route settles.
        guard format.sampleRate > 0 else { return }

        engine.attach(mixer)
        engine.connect(input, to: mixer, format: format)
        engine.connect(mixer, to: engine.mainMixerNode, format: format)
        mixer.outputVolume = clamped(level)

        try engine.start()
        running = true
    }

    func stop() {
        guard running else { return }
        engine.stop()
        engine.reset()
        running = false
    }

    /// Foldback has to duck out of the way when somebody else is talking, or
    /// you are listening to yourself and them at once and neither is clear.
    func setSuppressed(_ suppressed: Bool) {
        mixer.outputVolume = suppressed ? clamped(level) * 0.25 : clamped(level)
    }

    private func clamped(_ value: Float) -> Float {
        min(max(value, 0), 0.45)
    }
}
