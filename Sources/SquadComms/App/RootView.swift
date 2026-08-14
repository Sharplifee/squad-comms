import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionManager

    var body: some View {
        Group {
            switch session.state {
            case .idle:                 JoinView()
            case .connecting:           ConnectingView()
            case .connected:            HomeView()
            case .failed(let message):  FailureView(message: message)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.state)
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
