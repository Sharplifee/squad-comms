import Speech
import AVFoundation

/// Hands-free voice commands. Differentiator: you never touch the phone.
///
/// Two paths run in sequence. The keyword table fires on a partial
/// transcription so the exact phrases stay snappy. Anything the table misses
/// goes to `IntentParser` on the final transcription, which parses real spoken
/// intent server-side and catches the phrasings a table can't enumerate.
///
/// Every stage here logs to `Log.commands`. This chain shipped six times
/// without ever executing, so "it should work" is not evidence — follow it with
///
///     log stream --device --predicate 'category == "commands"'
final class CommandEngine {

    /// `partialSafe` phrases fire the moment they appear in a partial
    /// transcription. Bare words do not: "mute" is a live prefix of both
    /// "mute me" and "mute all", so firing it on a partial would pre-empt
    /// "mute all" with the wrong action every time. Those wait for the final
    /// transcription, when the utterance is known to be complete.
    enum Command: String, CaseIterable {
        case muteAll      = "mute all"
        case unmuteAll    = "unmute all"
        case muteMe       = "mute me"
        case unmuteMe     = "unmute me"
        case rewind       = "rewind that"
        case leave        = "close the line"
        // Bare forms. The table previously had no plain "mute", so the single
        // most likely thing anyone says went to the model path — which was
        // returning 401 on every request.
        case mute         = "mute"
        case unmute       = "unmute"

        var partialSafe: Bool {
            switch self {
            case .mute, .unmute: return false
            default:             return true
            }
        }
    }

    private let recognizer = SFSpeechRecognizer()
    private let parser = IntentParser()

    /// `append` runs on the audio render thread while the recognition callback
    /// swaps these out. Guard the references — an unsynchronised swap here is a
    /// use-after-free, not a dropped word.
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Bumped on every start/stop. A callback belonging to a superseded task
    /// must not be able to restart the current one.
    private var generation = 0
    private var stopping = false
    private var buffersSeen = 0
    private var loggedFirstBuffer = false

    /// Exact keyword hits. Unchanged — existing callers keep working.
    var onCommand: ((Command) -> Void)?

    /// Every resolved intent, keyword or model. Richer than `onCommand`:
    /// carries volume, target and confidence.
    var onIntent: ((VoiceIntent) -> Void)?

    /// Supplies the current squad roster so the parser can resolve names.
    var rosterProvider: (() -> [String])?

    func requestAuthorization(_ done: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            Log.commands.info("speech authorization status=\(status.rawValue, privacy: .public) (3 == authorized)")
            DispatchQueue.main.async { done(status == .authorized) }
        }
    }

    func start(on engine: AVAudioEngine) {
        // Each of these three returns was silent before. A dead command chain
        // and a disabled one looked identical from outside.
        guard PreferencesStore.shared.current.voiceCommandsEnabled else {
            Log.commands.error("start aborted: voiceCommandsEnabled == false")
            return
        }
        guard let recognizer else {
            Log.commands.error("start aborted: SFSpeechRecognizer() returned nil for locale \(Locale.current.identifier, privacy: .public)")
            return
        }
        guard recognizer.isAvailable else {
            Log.commands.error("start aborted: recognizer unavailable (locale \(recognizer.locale.identifier, privacy: .public))")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Transcription stays on the device. Only the resulting text is ever
        // sent anywhere, and only when the keyword table has already missed.
        //
        // Forcing this on a recognizer without the on-device asset installed
        // makes the task fail immediately with kAFAssistantErrorDomain 1101 and
        // never produce a single result, so ask before demanding.
        let onDevice = recognizer.supportsOnDeviceRecognition
        request.requiresOnDeviceRecognition = onDevice
        if !onDevice {
            Log.commands.error("on-device recognition unsupported for \(recognizer.locale.identifier, privacy: .public) — falling back to server transcription")
        }

        lock.lock()
        generation += 1
        let myGeneration = generation
        stopping = false
        self.request = request
        lock.unlock()

        Log.commands.info("recognition task starting gen=\(myGeneration, privacy: .public) locale=\(recognizer.locale.identifier, privacy: .public) onDevice=\(onDevice, privacy: .public)")

        let started = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let error {
                let ns = error as NSError
                // A cancel we asked for is not a failure. Anything else killed
                // the task permanently — the old code discarded this entirely,
                // which is how commands could die at launch and stay dead.
                self.lock.lock()
                let deliberate = self.stopping || myGeneration != self.generation
                self.lock.unlock()
                if deliberate {
                    Log.commands.debug("recognition ended (deliberate) gen=\(myGeneration, privacy: .public)")
                } else {
                    Log.commands.error("recognition FAILED gen=\(myGeneration, privacy: .public) domain=\(ns.domain, privacy: .public) code=\(ns.code, privacy: .public) \(ns.localizedDescription, privacy: .public) — restarting in 1s")
                    self.scheduleRestart(on: engine, after: 1.0, from: myGeneration)
                }
                return
            }

            guard let result else { return }
            let text = result.bestTranscription.formattedString.lowercased()
            Log.commands.info("transcription final=\(result.isFinal, privacy: .public) text=\(text, privacy: .public)")

            if let command = Self.match(text, isFinal: result.isFinal) {
                Log.commands.info("KEYWORD HIT '\(command.rawValue, privacy: .public)' -> action \(command.action.rawValue, privacy: .public)")
                self.onCommand?(command)
                self.onIntent?(VoiceIntent(action: command.action, volume: nil, target: nil,
                                           confidence: 1, source: .keyword))
                self.scheduleRestart(on: engine, after: 0, from: myGeneration)
                return
            }

            guard result.isFinal else { return }
            let roster = self.rosterProvider?() ?? []
            Task { [weak self] in
                guard let self else { return }
                let intent = await self.parser.parse(text, roster: roster)
                Log.commands.info("parser returned action=\(intent.action.rawValue, privacy: .public) source=\(intent.source.rawValue, privacy: .public) confidence=\(intent.confidence, privacy: .public)")
                guard intent.action != .unknown else {
                    // Still restart: a final result ends the task, so skipping
                    // this left the engine permanently deaf after the first
                    // unrecognised utterance.
                    self.scheduleRestart(on: engine, after: 0, from: myGeneration)
                    return
                }
                await MainActor.run {
                    self.onIntent?(intent)
                    self.scheduleRestart(on: engine, after: 0, from: myGeneration)
                }
            }
        }

        lock.lock()
        self.task = started
        lock.unlock()
    }

    /// Called from the audio render thread. Keep it cheap and never log per
    /// buffer — os_log on the render thread distorts the VAD timing it shares.
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let request = self.request
        buffersSeen += 1
        let count = buffersSeen
        let first = !loggedFirstBuffer && request != nil
        if first { loggedFirstBuffer = true }
        lock.unlock()

        guard let request else { return }
        request.append(buffer)

        if first {
            Log.commands.info("FIRST BUFFER reached recognition: frames=\(buffer.frameLength, privacy: .public) rate=\(buffer.format.sampleRate, privacy: .public) ch=\(buffer.format.channelCount, privacy: .public)")
        } else if count % 250 == 0 {
            Log.commands.debug("buffers appended: \(count, privacy: .public)")
        }
    }

    func stop() {
        lock.lock()
        stopping = true
        generation += 1
        let task = self.task
        let request = self.request
        self.task = nil
        self.request = nil
        loggedFirstBuffer = false
        lock.unlock()

        Log.commands.info("recognition stopping")
        request?.endAudio()
        task?.cancel()
    }

    /// Restarts are always hopped off the recognition callback. Cancelling a
    /// task from inside its own completion handler is re-entrant, and the
    /// generation check drops restarts asked for by a superseded task.
    private func scheduleRestart(on engine: AVAudioEngine, after delay: TimeInterval, from generation: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let stale = self.stopping || generation != self.generation
            self.lock.unlock()
            guard !stale else {
                Log.commands.debug("restart skipped (stale gen=\(generation, privacy: .public))")
                return
            }
            self.stop()
            self.lock.lock(); self.stopping = false; self.lock.unlock()
            self.start(on: engine)
        }
    }

    /// Longest phrase first. Declaration order was subtly wrong: matching is
    /// `hasSuffix`, and "unmute all" ends with "mute all", so the old loop
    /// resolved every "unmute all" to `muteAll` — the exact opposite command.
    /// Sorting by length makes the longer phrase win.
    static let byLengthDescending = Command.allCases.sorted { $0.rawValue.count > $1.rawValue.count }

    static func match(_ text: String, isFinal: Bool) -> Command? {
        for command in byLengthDescending where command.partialSafe || isFinal {
            if text.hasSuffix(command.rawValue) { return command }
        }
        return nil
    }
}
