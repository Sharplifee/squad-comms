import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionManager
    @State private var onboarded = UserDefaults.standard.bool(forKey: "squadcomms.onboarded")

    var body: some View {
        Group {
            if !onboarded {
                // Ask once, before anything connects. Without this the squad is
                // named after the default "Me" and three system prompts fire
                // unexplained over a spinner.
                OnboardingView(isComplete: $onboarded)
            } else {
                connected
            }
        }
        .animation(.easeInOut(duration: 0.25), value: onboarded)
        .task { await session.loadBlocks() }
    }

    /// The app opens on the dashboard. Always.
    ///
    /// It used to open a line on appear, which meant launch was a spinner
    /// while a squad was created or rejoined before anything was usable. There
    /// is no reason to hold a line open before somebody asks for one — opening
    /// the app is not the same as starting a session.
    private var connected: some View {
        Group {
            switch session.state {
            case .connecting:           ConnectingView()
            // There is deliberately no failure route. Nothing that can go
            // wrong here justifies replacing the whole app with a wall — a
            // taken code or a dropped connection is information you act on
            // from the screen you were already on. Failures surface as
            // session.notice, inline.
            default:                    MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.state)
    }
}

/// The brief moment between choosing a code and the room being live.
///
/// This only appears when you deliberately opened a line — never at launch,
/// where the app goes straight to the dashboard.
struct ConnectingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text("Opening the line")
                .font(.callout)
                .foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}
