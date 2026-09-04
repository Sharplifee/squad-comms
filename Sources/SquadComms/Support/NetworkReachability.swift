import Network
import Foundation

/// One shared answer to "is there a network at all".
///
/// Needed synchronously at the moment a failure is being described, so it
/// keeps a cached flag rather than making the caller await a path update.
/// The distinction matters: "you're offline" and "the server didn't answer"
/// send someone to two completely different fixes.
@MainActor
final class ReachabilityWatcher: ObservableObject {
    /// Published so a banner can appear the moment the network drops, rather
    /// than only when somebody tries something and it fails.
    @Published private(set) var isOnline = true

    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.isOnline = (path.status == .satisfied) }
        }
        monitor.start(queue: DispatchQueue(label: "com.squadcomms.reachability.watch"))
    }
}

enum NetworkReachability {
    private static let monitor: NWPathMonitor = {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            online = (path.status == .satisfied)
        }
        monitor.start(queue: DispatchQueue(label: "com.squadcomms.reachability"))
        return monitor
    }()

    private static var online = true

    static var isOnline: Bool {
        _ = monitor          // force the lazy start on first use
        return online
    }
}
