import SwiftUI
import UIKit

@main
struct SquadCommsApp: App {
    @Environment(\.scenePhase) private var scenePhase
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
                .onChange(of: scenePhase) { _, phase in
                    // The radar updates a picture nobody can see while
                    // backgrounded, and BLE scanning is not free.
                    session.proximity.setSuspended(phase != .active)
                    // Permissions can be revoked in Settings while we are
                    // backgrounded. iOS says nothing — the audio just stops
                    // arriving, which is indistinguishable from a network
                    // problem unless we check.
                    if phase == .active { session.recheckMicrophonePermission() }
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // VoIP push is deliberately gone. Since iOS 13 every VoIP push must
        // report an incoming call to CallKit or iOS terminates the app and
        // eventually stops delivering pushes altogether — and a walkie-talkie
        // must not ring like a phone call. Accepted tradeoff: once iOS kills
        // the app, nobody can pull you back automatically.
        KeepAlive.registerTask()
        return true
    }
}
