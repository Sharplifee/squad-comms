import SwiftUI

/// Three tabs.
///
/// Five collapsed to Line, Squad and Settings. Diagnostics was never a place
/// you go on purpose — it is where you look when something is wrong, which is
/// a Settings errand. Contacts folded into the Line screen's nearby flow and
/// into Settings, because finding somebody is part of opening a line, not a
/// separate destination.
struct MainTabView: View {
    @EnvironmentObject private var session: SessionManager
    @StateObject private var focus = FocusModeController()
    @StateObject private var toasts = ToastCenter()

    var body: some View {
        ZStack {
            TabView {
                LineView(focus: focus)
                    .tabItem { Label("Line", systemImage: "waveform") }

                SquadTabView()
                    .tabItem { Label("Squad", systemImage: "person.2") }
                    .badge(session.members.count)

                SettingsHome()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
            .tint(Theme.text)

            if focus.isActive {
                FocusOverlay(focus: focus).ignoresSafeArea()
            }
        }
        .toasts(toasts)
        .environmentObject(toasts)
        .animation(.easeInOut(duration: 0.2), value: focus.isActive)
        .onAppear { focus.attach(session) }
    }
}

/// One row per person: name, live state, volume inline. Expand for routing and
/// Block and report. Your own card pinned at the top.
struct SquadTabView: View {
    @EnvironmentObject private var session: SessionManager
    @EnvironmentObject private var audio: AudioCoordinator

    var body: some View {
        NavigationStack {
            Group {
                if session.squad == nil {
                    ContentUnavailableView(
                        "No line open",
                        systemImage: "waveform",
                        description: Text("Open one from the Line tab and your squad shows up here.")
                    )
                } else {
                    List {
                        Section { selfRow }
                        if session.members.isEmpty {
                            Section {
                                Text("Nobody else is on yet. Share your code and they drop straight in.")
                                    .font(.system(size: 13.5, design: .rounded))
                                    .foregroundStyle(Theme.textDim)
                            }
                        } else {
                            ForEach(session.members) { member in
                                Section { RoutingCard(member: member) }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Theme.base)
                }
            }
            .navigationTitle("Squad")
        }
    }

    private var selfRow: some View {
        HStack(spacing: 12) {
            Image(systemName: audio.isTransmitting ? "waveform" : "person.fill")
                .foregroundStyle(audio.isTransmitting ? Theme.signal : Theme.textFaint)
                .frame(width: 22)
            Text(PreferencesStore.shared.current.displayName)
                .font(.system(size: 15, design: .rounded))
            Text("YOU")
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(Theme.textDim)
            Spacer()
        }
    }
}

/// One person, both directions of the connection, and the way to stop them.
struct RoutingCard: View {
    let member: Member
    @EnvironmentObject private var session: SessionManager
    @State private var reporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                Image(systemName: member.isSpeaking && !member.isMutedByMe ? "waveform" : "person.fill")
                    .foregroundStyle(member.isSpeaking && !member.isMutedByMe
                                     ? Theme.signal : Theme.textFaint)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(member.displayName).font(.system(size: 15, design: .rounded))
                    if member.nearby {
                        Text("Nearby").font(.caption).foregroundStyle(Theme.textDim)
                    }
                }
                Spacer()
                Text("\(Int(member.volume * 100))%")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.textDim)
            }

            Slider(value: Binding(
                get: { member.volume },
                set: { session.setVolume($0, for: member) }
            ), in: 0...1)
            .tint(Theme.text)
            .disabled(member.isMutedByMe)

            Toggle("I hear them", isOn: Binding(
                get: { !member.isMutedByMe },
                set: { session.setMuted(!$0, for: member); Haptics.selection() }
            ))
            .font(.system(size: 14, design: .rounded))

            Toggle("They hear me", isOn: Binding(
                get: { !member.isMutedToThem },
                set: { session.setMutedToThem(!$0, for: member); Haptics.selection() }
            ))
            .font(.system(size: 14, design: .rounded))

            Text("Hold this card to talk to \(member.displayName) only")
                .font(.caption)
                .foregroundStyle(Theme.dim)

            Button(role: .destructive) { reporting = true } label: {
                Text("Block and report")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            }
            .sheet(isPresented: $reporting) { ReportSheet(member: member) }
        }
        .padding(.vertical, 4)
        .tint(Theme.signal)
        .contentShape(Rectangle())
        // The private line had a complete implementation — distinct earcons at
        // both ends, reliable routing events, everyone else ducked to 12% —
        // and no way to trigger it after the redesign replaced the row that
        // held the gesture. It has been dead since.
        .gesture(
            LongPressGesture(minimumDuration: 0.35)
                .onEnded { _ in session.beginPrivateLine(to: member) }
                .sequenced(before: DragGesture(minimumDistance: 0))
                .onEnded { _ in session.endPrivateLine() }
        )
    }
}
