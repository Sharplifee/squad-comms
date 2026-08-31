import SwiftUI

/// Four tabs.
///
/// Everything used to live on one scrolling screen with a gear icon, which
/// meant the mixing controls, the diagnostics and the squad list all competed
/// for the same space and none of them had room. Tabs give each its own
/// surface and make the app navigable without scrolling past things you did
/// not want.
struct MainTabView: View {
    @EnvironmentObject private var session: SessionManager
    @StateObject private var focus = FocusModeController()

    var body: some View {
        ZStack {
            TabView {
                HomeView(focus: focus)
                    .tabItem { Label("Home", systemImage: "waveform.circle") }

                SquadTabView()
                    .tabItem { Label("Squad", systemImage: "person.2") }
                    .badge(session.members.count)

                AudioTabView()
                    .tabItem { Label("Audio", systemImage: "slider.horizontal.3") }

                DiagnosticsView()
                    .tabItem { Label("Status", systemImage: "waveform.path.ecg") }
            }

            if focus.isActive {
                FocusOverlay(focus: focus)
                    .ignoresSafeArea()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: focus.isActive)
        .onAppear { focus.attach(session) }
    }
}

/// The squad on its own surface, with your own card pinned at the top.
struct SquadTabView: View {
    @EnvironmentObject private var session: SessionManager
    @EnvironmentObject private var audio: AudioCoordinator

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: audio.isTransmitting ? "waveform" : "person.fill")
                            .font(.body)
                            .foregroundStyle(audio.isTransmitting ? Theme.live : Theme.textFaint)
                            .frame(width: 22)
                        Text(PreferencesStore.shared.current.displayName)
                        Text("YOU")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.surfaceAlt, in: Capsule())
                            .foregroundStyle(Theme.textDim)
                        Spacer()
                    }
                }

                if session.members.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "Nobody else is on",
                            systemImage: "person.2.slash",
                            description: Text("Share your code from the Home tab and they drop straight in.")
                        )
                        .listRowBackground(Color.clear)
                    }
                } else {
                    MixerView()
                }
            }
            .navigationTitle("Squad")
        }
    }
}
