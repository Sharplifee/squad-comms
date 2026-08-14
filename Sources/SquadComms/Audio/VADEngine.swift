import AVFoundation
import Combine

/// Voice activity detection. This is what removes the button.
/// SILENCE -> ONSET -> TRANSMITTING -> TRAILING -> SILENCE
final class VADEngine: ObservableObject {

    enum State: Equatable { case silence, transmitting, trailing }

    @Published private(set) var state: State = .silence
    @Published private(set) var inputLevelDB: Float = -60

    private let engine = AVAudioEngine()
    private var lastSpeechAt: Date = .distantPast
    private var prefs: Preferences { PreferencesStore.shared.current }

    var onTransmissionBegan: (() -> Void)?
    var onTransmissionEnded: (() -> Void)?

    func start() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.process(buffer)
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        state = .silence
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        let db = Self.rmsDB(buffer)
        DispatchQueue.main.async { self.inputLevelDB = db }

        let now = Date()
        let onset = prefs.vadOnsetDB
        let floor = prefs.vadSilenceDB
        let trailing = TimeInterval(prefs.trailingMS) / 1000.0

        switch state {
        case .silence:
            guard prefs.openMic, db > onset else { return }
            lastSpeechAt = now
            DispatchQueue.main.async {
                self.state = .transmitting
                self.onTransmissionBegan?()
            }

        case .transmitting:
            if db > floor {
                lastSpeechAt = now
            } else if now.timeIntervalSince(lastSpeechAt) > 0.1 {
                DispatchQueue.main.async { self.state = .trailing }
            }

        case .trailing:
            if db > onset {
                lastSpeechAt = now
                DispatchQueue.main.async { self.state = .transmitting }
            } else if now.timeIntervalSince(lastSpeechAt) > trailing {
                DispatchQueue.main.async {
                    self.state = .silence
                    self.onTransmissionEnded?()
                }
            }
        }
    }

    /// Push-to-talk path for when open mic is switched off.
    func manualBegin() {
        guard state == .silence else { return }
        state = .transmitting
        onTransmissionBegan?()
    }

    func manualEnd() {
        guard state != .silence else { return }
        state = .silence
        onTransmissionEnded?()
    }

    private static func rmsDB(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return -60 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return -60 }
        var sum: Float = 0
        for i in 0..<count { sum += channel[i] * channel[i] }
        let rms = sqrt(sum / Float(count))
        return rms > 0 ? 20 * log10(rms) : -60
    }
}
