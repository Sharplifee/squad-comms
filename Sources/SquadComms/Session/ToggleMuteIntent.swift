import AppIntents
import Foundation

/// Mute from the lock screen without opening the app.
///
/// `LiveActivityIntent` rather than a plain `AppIntent`: a plain one runs
/// inside the widget extension, which cannot reach the running session, and
/// would need an app group plus polling to pass a message back. A
/// LiveActivityIntent runs in the CONTAINING APP's process, so it can touch
/// the session directly and the mute is immediate rather than up to a second
/// late.
struct ToggleMuteIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Toggle microphone"
    static var description = IntentDescription("Mute or unmute yourself on the open line.")
    /// The entire point is not having to open the app.
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        MuteBridge.shared.toggle?()
        return .result()
    }
}

/// How the intent reaches the live session.
///
/// The intent is a value type constructed by the system, so it cannot hold a
/// reference to SessionManager. This is the one hook it can find, set once
/// while a line is open and cleared when it closes.
@MainActor
final class MuteBridge {
    static let shared = MuteBridge()
    private init() {}

    var toggle: (() -> Void)?
}
