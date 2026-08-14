import PushKit
import Foundation

/// Keeps the socket alive when the app is fully backgrounded and the phone
/// is in a pocket with the screen off. Same stack FaceTime and Discord use.
final class VoIPPushManager: NSObject {
    static let shared = VoIPPushManager()
    private var registry: PKPushRegistry?

    func register() {
        let registry = PKPushRegistry(queue: .main)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
        self.registry = registry
    }
}

extension VoIPPushManager: PKPushRegistryDelegate {
    func pushRegistry(_ registry: PKPushRegistry,
                      didUpdate credentials: PKPushCredentials,
                      for type: PKPushType) {
        let token = credentials.token.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: "squadcomms.voipToken")
    }

    func pushRegistry(_ registry: PKPushRegistry,
                      didReceiveIncomingPushWith payload: PKPushPayload,
                      for type: PKPushType,
                      completion: @escaping () -> Void) {
        NotificationCenter.default.post(name: .squadWakeRequested, object: nil)
        completion()
    }
}

extension Notification.Name {
    static let squadWakeRequested = Notification.Name("squadWakeRequested")
}
