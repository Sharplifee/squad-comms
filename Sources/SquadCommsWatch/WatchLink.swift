import Foundation
import OSLog
import WatchConnectivity

/// The watch target compiles separately from the app, so it cannot see the
/// app's Log. One category is all it needs.
private enum Log {
    static let watch = Logger(subsystem: "com.connor.openline.watchkitapp", category: "watch")
}

/// The wrist's view of the line.
///
/// Deliberately thin. The watch holds no session and no audio — it mirrors
/// state and sends one instruction. Running the audio stack on both devices
/// would double the battery cost of the thing whose whole selling point is
/// lasting a 90 minute workout.
///
/// `sendMessage` is used rather than application context because a mute needs
/// to take effect now, not at the system's convenience. If the phone is
/// unreachable the mute is applied optimistically on the watch and reconciled
/// on the next state update — showing "Muted" when you are not would be worse
/// than a brief disagreement.
@MainActor
final class WatchLink: NSObject, ObservableObject {
    @Published private(set) var onLine = false
    @Published private(set) var muted = false
    @Published private(set) var talking: [String] = []

    private var session: WCSession?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
    }

    func toggleMute() {
        let next = !muted
        muted = next
        session?.sendMessage(["action": "setMuted", "muted": next],
                             replyHandler: nil,
                             errorHandler: { error in
            Log.watch.error("mute did not reach the phone: \(error.localizedDescription, privacy: .public)")
        })
    }

    private func apply(_ payload: [String: Any]) {
        onLine  = payload["onLine"] as? Bool ?? false
        muted   = payload["muted"] as? Bool ?? false
        talking = payload["talking"] as? [String] ?? []
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {}

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.apply(message) }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext context: [String: Any]) {
        Task { @MainActor in self.apply(context) }
    }
}
