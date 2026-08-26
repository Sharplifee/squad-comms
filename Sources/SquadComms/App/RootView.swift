import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionManager

    var body: some View {
        Group {
            switch session.state {
            // Nothing to enter. The line opens itself.
            case .idle:                 OpeningView()
            case .connecting:           ConnectingView()
            case .connected:            HomeView()
            case .failed(let message):  FailureView(message: message)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.state)
        .task { await session.openLine() }
    }
}

/// Shown for the moment between launch and the line being up. Deliberately
/// not a form — there is nothing here for anyone to fill in.
struct OpeningView: View {
    var body: some View {
        VStack(spacing: 14) {
            Text("squad comms")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.text)
            Text("Opening the line")
                .font(.callout)
                .foregroundStyle(Theme.textDim)
            ProgressView().controlSize(.small).padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

struct ConnectingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Opening the line").font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
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
            Button("Try again") { session.reset() }.buttonStyle(PrimaryButton())
                .frame(maxWidth: 220)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}
