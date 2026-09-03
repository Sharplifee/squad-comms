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
            case .failed(let message):  FailureView(message: message)
            default:                    MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.state)
    }
}

struct FailureView: View {
    let message: String
    @EnvironmentObject private var session: SessionManager

    var body: some View {
        VStack(spacing: 20) {
            Text("Couldn't connect").font(.title2.weight(.semibold))
            Text(message)
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            // reset() alone only returned to .idle and left the user staring
            // at a spinner, because nothing re-drove the connect. Retry has to
            // actually retry.
            Button("Try again") {
                Task {
                    session.reset()
                    // Retry means rejoin the code we were told to open, not
                    // create a fresh squad — creating one would strand the
                    // person you were trying to reach on the original code.
                    if let code = UserDefaults.standard.string(forKey: "squadcomms.lastCode") {
                        await session.join(code: code)
                    }
                }
            }
            .buttonStyle(PrimaryButton())
            .frame(maxWidth: 220)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
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
