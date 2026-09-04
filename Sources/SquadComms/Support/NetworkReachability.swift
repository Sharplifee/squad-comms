import Network
import Foundation
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
