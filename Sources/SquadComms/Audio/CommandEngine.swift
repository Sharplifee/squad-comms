import Speech
import AVFoundation

/// Hands-free voice commands. Differentiator: you never touch the phone.
///
/// Two paths run in sequence. The keyword table fires instantly on a partial
/// transcription so the exact phrases stay snappy. Anything the table misses
/// goes to `IntentParser` on the final transcription, which parses real spoken
/// intent server-side and catches the phrasings a table can't enumerate.
final class CommandEngine {

    enum Command: String, CaseIterable {
        case muteAll      = "mute all"
        case unmuteAll    = "unmute all"
        case muteMe       = "mute me"
        case unmuteMe     = "unmute me"
        case rewind       = "rewind that"
        case leave        = "close the line"
    }

    private let recognizer = SFSpeechRecognizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let parser = IntentParser()

    /// Exact keyword hits. Unchanged — existing callers keep working.
    var onCommand: ((Command) -> Void)?

    /// Every resolved intent, keyword or model. Richer than `onCommand`:
    /// carries volume, target and confidence.
    var onIntent: ((VoiceIntent) -> Void)?

    /// Supplies the current squad roster so the parser can resolve names.
    var rosterProvider: (() -> [String])?

    func requestAuthorization(_ done: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async { done(status == .authorized) }
        }
    }

    func start(on engine: AVAudioEngine) {
        guard PreferencesStore.shared.current.voiceCommandsEnabled,
              let recognizer, recognizer.isAvailable else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Transcription stays on the device. Only the resulting text is ever
        // sent anywhere, and only when the keyword table has already missed.
        request.requiresOnDeviceRecognition = true
        self.request = request

        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let self, let result else { return }
            let text = result.bestTranscription.formattedString.lowercased()

            for command in Command.allCases where text.hasSuffix(command.rawValue) {
                self.onCommand?(command)
                self.onIntent?(VoiceIntent(action: command.action, volume: nil, target: nil,
                                           confidence: 1, source: .keyword))
                self.restart(on: engine)
                return
            }

            guard result.isFinal else { return }
            let roster = self.rosterProvider?() ?? []
            Task { [weak self] in
                guard let self else { return }
                let intent = await self.parser.parse(text, roster: roster)
                guard intent.action != .unknown else { return }
                await MainActor.run {
                    self.onIntent?(intent)
                    self.restart(on: engine)
                }
            }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }

    func stop() {
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
    }

    private func restart(on engine: AVAudioEngine) {
        stop()
        start(on: engine)
    }
}
