import BackgroundTasks
import Foundation

/// 60-second heartbeat so the LiveKit connection survives long backgrounding.
enum KeepAlive {
    static let identifier = "com.connor.openline.keepalive"

    static func registerTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            schedule()
            NotificationCenter.default.post(name: .squadWakeRequested, object: nil)
            task.setTaskCompleted(success: true)
        }
        schedule()
    }

    static func schedule() {
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        request.requiresNetworkConnectivity = true
        try? BGTaskScheduler.shared.submit(request)
    }
}


extension Notification.Name {
    /// Posted when a background task wants the session re-checked. Previously
    /// declared alongside the VoIP push manager, which is gone.
    static let squadWakeRequested = Notification.Name("squadWakeRequested")
}
