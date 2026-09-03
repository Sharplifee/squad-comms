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
    @StateObject private var toasts = ToastCenter()

    var body: some View {
        ZStack {
            TabView {
                HomeView(focus: focus)
                    .tabItem { Label("Home", systemImage: "waveform.circle") }

                SquadTabView()
                    .tabItem { Label("Squad", systemImage: "person.2") }
                    .badge(session.members.count)

                ContactsView(backend: session.backend)
                    .tabItem { Label("Contacts", systemImage: "person.crop.circle") }

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
        .toasts(toasts)
        .environmentObject(toasts)
        .animation(.easeInOut(duration: 0.2), value: focus.isActive)
        .onAppear { focus.attach(session) }
    }
}

/// The squad on its own surface, with your own card pinned at the top.
struct SquadTabView: View {
    @EnvironmentObject private var session: SessionManager
    @EnvironmentObject private var audio: AudioCoordinator
    @State private var isList = PreferencesStore.shared.current.squadViewIsList

    var body: some View {
        NavigationStack {
            Group {
                if session.squad == nil {
                    ContentUnavailableView(
                        "No line open",
                        systemImage: "dot.radiowaves.left.and.right",
                        description: Text("Open a line from the Home tab and your squad shows up here.")
                    )
                } else if session.members.isEmpty {
                    ContentUnavailableView(
                        "Nobody else is on",
                        systemImage: "person.2.slash",
                        description: Text("Share your code and they drop straight in.")
                    )
                } else if isList {
                    listView
                } else {
                    tileView
                }
            }
            .navigationTitle("Squad")
            .toolbar {
                if !session.members.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isList.toggle()
                            PreferencesStore.shared.update { $0.squadViewIsList = isList }
                            Haptics.selection()
                        } label: {
                            Image(systemName: isList ? "square.grid.2x2" : "list.bullet")
                        }
                    }
                }
            }
        }
    }

    /// Tiles: faces you can read at arm's length. Tap to mute.
    private var tileView: some View {
        ScrollView {
            VStack(spacing: 14) {
                selfCard
                ParticipantGrid(members: session.members)
            }
            .padding(16)
        }
    }

    /// List: the controls. One card per person with their level and both
    /// directions of the connection stated separately.
    private var listView: some View {
        List {
            Section { selfRow }
            ForEach(session.members) { member in
                Section {
                    RoutingCard(member: member)
                }
            }
        }
    }

    private var selfRow: some View {
        HStack(spacing: 12) {
            Image(systemName: audio.isTransmitting ? "waveform" : "person.fill")
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

    private var selfCard: some View {
        HStack(spacing: 12) {
            Image(systemName: audio.isTransmitting ? "waveform" : "person.fill")
                .foregroundStyle(audio.isTransmitting ? Theme.live : Theme.textFaint)
            Text(PreferencesStore.shared.current.displayName)
            Text("YOU")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Theme.surfaceAlt, in: Capsule())
                .foregroundStyle(Theme.textDim)
            Spacer()
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// One person, both directions.
///
/// Hearing them and them hearing you are separate switches because they are
/// separate needs. Listening to somebody without them hearing you mid-set is
/// normal; so is talking to someone whose mic has a leaf blower behind it that
/// you have muted.
struct RoutingCard: View {
    let member: Member
    @EnvironmentObject private var session: SessionManager
    @State private var reporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                Image(systemName: member.isSpeaking && !member.isMutedByMe ? "waveform" : "person.fill")
                    .foregroundStyle(member.isSpeaking && !member.isMutedByMe ? Theme.live : Theme.textFaint)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(member.displayName)
                    if member.nearby {
                        Text("Nearby").font(.caption).foregroundStyle(Theme.textDim)
                    }
                }
                Spacer()
                Text("\(Int(member.volume * 100))%")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textDim)
                    .monospacedDigit()
            }

            Slider(
                value: Binding(
                    get: { member.volume },
                    set: { session.setVolume($0, for: member) }
                ),
                in: 0...1
            )
            .disabled(member.isMutedByMe)

            Toggle("I hear them", isOn: Binding(
                get: { !member.isMutedByMe },
                set: { session.setMuted(!$0, for: member); Haptics.selection() }
            ))
            .font(.subheadline)

            Toggle("They hear me", isOn: Binding(
                get: { !member.isMutedToThem },
                set: { session.setMutedToThem(!$0, for: member); Haptics.selection() }
            ))
            .font(.subheadline)

            Button(role: .destructive) { reporting = true } label: {
                Label("Block and report", systemImage: "hand.raised")
                    .font(.subheadline)
            }
            .sheet(isPresented: $reporting) { ReportSheet(member: member) }
        }
        .padding(.vertical, 4)
    }
}
