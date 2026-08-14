import SwiftUI
import UIKit

@main
struct SquadCommsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = SessionManager()
    @StateObject private var audio = AudioCoordinator()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(audio)
                .preferredColorScheme(.dark)
                .task {
                    Telemetry.start()
                    audio.attach(session: session)
                    await session.restoreLastSession()
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        VoIPPushManager.shared.register()
        KeepAlive.registerTask()
        return true
    }
}
