import Network
import Foundation

/// One shared answer to "is there a network at all".
///
/// Needed synchronously at the moment a failure is being described, so it
/// caches a flag rather than making the caller await a path update. The
/// distinction it enables matters: "you're offline" and "the server didn't
/// answer" send somebody to two completely different fixes.
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
