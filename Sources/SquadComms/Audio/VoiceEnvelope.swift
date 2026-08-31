import Foundation
import QuartzCore

/// Gain envelope for incoming voice.
///
/// A voice that switches from silent to full in one buffer produces an audible
/// click, and one that cuts off the instant VAD releases chops the last
/// consonant off every sentence. Both read as cheap. Real intercoms ramp, and
/// the ramp shape matters more than the speed.
///
/// The curve is exponential rather than linear because loudness is perceived
/// logarithmically — a linear fade sounds like it hangs at the top and then
/// drops off a cliff at the end.
///
/// Attack is fast but not instant: 60 ms is under the ~100 ms it takes to
/// notice a delay, while still being long enough to avoid a transient click.
/// Release is much slower at 450 ms, with a 350 ms hold before it even starts,
/// so natural pauses mid-sentence do not make the voice pump up and down. That
/// asymmetry — fast in, slow out, hold between — is what every broadcast
/// compressor does and it is why they sound smooth.
final class VoiceEnvelope {

    private(set) var currentGain: Float = 0

    private var targetGain: Float = 0
    private var holdUntil: CFTimeInterval = 0
    private var lastTick: CFTimeInterval = CACurrentMediaTime()

    private let attack: Float = 0.060
    private let release: Float = 0.450
    private let hold: CFTimeInterval = 0.350

    /// Level the voice should reach when fully open, 0…1.
    var openLevel: Float = 1.0

    func open() {
        targetGain = openLevel
        holdUntil = 0
    }

    func close() {
        // Do not begin releasing immediately — wait out the hold so a breath
        // between words does not restart the whole envelope.
        holdUntil = CACurrentMediaTime() + hold
    }

    /// Advance the envelope. Call at the UI or audio tick rate; it is
    /// time-based rather than frame-based so an irregular tick cannot change
    /// how the fade sounds.
    @discardableResult
    func tick() -> Float {
        let now = CACurrentMediaTime()
        let delta = Float(min(now - lastTick, 0.1))   // clamp after a stall
        lastTick = now

        if holdUntil > 0, now >= holdUntil {
            targetGain = 0
            holdUntil = 0
        }

        let timeConstant = targetGain > currentGain ? attack : release
        // One-pole exponential smoothing. coefficient = 1 - e^(-dt/tau)
        let coefficient = 1 - exp(-delta / timeConstant)
        currentGain += (targetGain - currentGain) * coefficient

        // Snap the last sliver so a track never sits at 0.001 forever, which
        // keeps a decoder awake for no reason.
        if abs(targetGain - currentGain) < 0.002 { currentGain = targetGain }

        return currentGain
    }

    func reset() {
        currentGain = 0
        targetGain = 0
        holdUntil = 0
        lastTick = CACurrentMediaTime()
    }
}
