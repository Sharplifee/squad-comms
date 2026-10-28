import SwiftUI
import UIKit

@main
struct SquadCommsApp: App {
    init() {
        EventLog.configure(url: "https://cqhugvirbxrxqhhbwklc.supabase.co", apiKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNxaHVndmlyYnhyeHFoaGJ3a2xjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk3MDcyMDAsImV4cCI6MjA5NTI4MzIwMH0.zZP0CvBoqYSBOc99NWHcJ87b_nOdYQ0g9WBMd8ssC9o", project: "squad-comms")   // append-only event log (public.event_log)
    }
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
                    session.attachWatch()
                    await session.restoreLastSession()
                }
                .onChange(of: scenePhase) { _, phase in
                    // A permission can be taken away in Settings while we are
                    // backgrounded. iOS never tells us — it just stops
                    // delivering audio — so returning to the foreground is the
                    // only moment we can notice.
                    if phase == .active { audio.recheckPermissions() }
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
