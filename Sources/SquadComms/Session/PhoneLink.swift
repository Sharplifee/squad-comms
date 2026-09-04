import Foundation
import WatchConnectivity

/// The phone's half of the wrist link.
///
/// Pushes a small state summary to the watch whenever what it shows would
/// change, and accepts exactly one instruction back: mute or unmute. Keeping
/// the surface this narrow is deliberate — every extra thing the watch can do
/// is another thing to look at mid-set, which is the opposite of the point.
///
/// State goes out via application context rather than messages. Context
/// coalesces and survives the watch app being asleep, which is its normal
/// condition; a message would be dropped and the wrist would show a stale
/// name. The instruction back comes as a message, because a mute has to land
/// immediately.
@MainActor
final class PhoneLink: NSObject {
    static let shared = PhoneLink()

    /// Set by SessionManager so an incoming mute can act on the live session.
    var onMuteRequest: ((Bool) -> Void)?

    private var session: WCSession?
    private var lastPayload: [String: Any] = [:]

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
    }

    func push(onLine: Bool, muted: Bool, talking: [String]) {
        guard let session, session.isPaired, session.isWatchAppInstalled else { return }

        let payload: [String: Any] = ["onLine": onLine, "muted": muted, "talking": talking]
        // Speech starts and stops constantly. Sending an identical payload
        // every time would spend battery on both devices to change nothing.
        guard !NSDictionary(dictionary: payload).isEqual(to: lastPayload) else { return }
        lastPayload = payload

        try? session.updateApplicationContext(payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }
}

extension PhoneLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard message["action"] as? String == "setMuted",
              let muted = message["muted"] as? Bool else { return }
        Task { @MainActor in PhoneLink.shared.onMuteRequest?(muted) }
    }
}
