import Speech
import AVFoundation

/// Hands-free voice commands. Differentiator: you never touch the phone.
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

    var onCommand: ((Command) -> Void)?

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
        request.requiresOnDeviceRecognition = true
        self.request = request

        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let self, let result else { return }
            let text = result.bestTranscription.formattedString.lowercased()
            for command in Command.allCases where text.hasSuffix(command.rawValue) {
                self.onCommand?(command)
                self.restart(on: engine)
                return
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
