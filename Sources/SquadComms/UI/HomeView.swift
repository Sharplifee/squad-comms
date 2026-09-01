import SwiftUI

/// The cockpit.
///
/// Ordered by what you actually need mid-set: who is here, whether your mic is
/// working, then the people, then the controls. The invite code only takes the
/// screen when you are alone, because at that point it is the entire product.
struct HomeView: View {
    @ObservedObject var focus: FocusModeController
    @EnvironmentObject private var session: SessionManager
    @EnvironmentObject private var audio: AudioCoordinator
    @State private var showSettings = false
    @State private var showJoin = false
    @State private var copied = false
    @State private var prefs = PreferencesStore.shared.current

    var body: some View {
        NavigationStack {
            List {
                if let from = session.privateLineFrom {
                    Section { privateLineRow(from) }
                }

                if session.members.isEmpty {
                    inviteSection
                } else {
                    radarSection
                    Section { ParticipantGrid(members: session.members) }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                    intercomSection
                }

                Section { MicCard() }

                presenceSection

                if !session.members.isEmpty {
                    Section { controlTrio }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(session.squad?.name ?? "Squad")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Leave", role: .destructive) { Task { await session.leave() } }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showJoin) { SwitchSquadSheet() }
        }
        .task { await audio.startListening() }
        .onDisappear { audio.stopListening() }
    }

    // MARK: - Radar

    private var radarSection: some View {
        Group {
            Section {
                PlateRadarView(
                    contacts: session.proximity.contacts,
                    names: Dictionary(uniqueKeysWithValues: session.members.map { ($0.id, $0.displayName) }),
                    speakingID: session.members.first(where: { $0.isSpeaking })?.id,
                    isScanning: session.proximity.isScanning
                )
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 300)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                .listRowBackground(Color.clear)
            }
            Section {
                RangeLoaderView(index: Binding(
                    get: { session.proximity.rangeIndex },
                    set: { session.proximity.rangeIndex = $0 }
                ))
            } footer: {
                Text("Bluetooth range only. It doesn't affect who can hear you.")
            }
        }
    }

    // MARK: - Intercom

    private var intercomSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Squad volume")
                    Spacer()
                    Text("\(Int(prefs.intercomVolume * 100))%")
                        .foregroundStyle(Theme.textDim)
                        .monospacedDigit()
                }
                Slider(value: $prefs.intercomVolume, in: 0...1)
            }
            .padding(.vertical, 2)
            .onChange(of: prefs.intercomVolume) { _, _ in
                PreferencesStore.shared.update { $0 = prefs }
                session.applyPreferences()
            }
        }
    }

    // MARK: - Presence

    private var presenceSection: some View {
        Section {
            Toggle(isOn: $prefs.ghostMode) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ghost mode")
                    Text("Nobody can see you on their radar.")
                        .font(.caption).foregroundStyle(Theme.textDim)
                }
            }
            Toggle(isOn: $prefs.privateSession) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Private squad")
                    Text("Only people with your code can join.")
                        .font(.caption).foregroundStyle(Theme.textDim)
                }
            }
        }
        .onChange(of: prefs) { _, new in
            PreferencesStore.shared.update { $0 = new }
            session.applyPresence()
        }
    }

    // MARK: - Controls

    private var controlTrio: some View {
        HStack(spacing: 11) {
            Menu {
                ForEach(FocusModeController.durations, id: \.self) { seconds in
                    Button("\(seconds) seconds") { focus.begin(seconds: seconds) }
                }
            } label: {
                controlButton("Focus", "moon", tint: Theme.accent)
            }

            Button {
                session.muteAll(!allMuted)
                Haptics.selection()
            } label: {
                controlButton(allMuted ? "Unmute all" : "Mute all",
                              allMuted ? "speaker.wave.2" : "speaker.slash",
                              tint: Theme.accent)
            }
            .buttonStyle(.plain)

            Button {
                Task { await session.leave() }
            } label: {
                controlButton("End", "phone.down.fill", tint: Theme.muted)
            }
            .buttonStyle(.plain)
        }
    }

    private func controlButton(_ title: String, _ symbol: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 17))
            Text(title).font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .foregroundStyle(tint)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var allMuted: Bool {
        !session.members.isEmpty && session.members.allSatisfy(\.isMutedByMe)
    }

    // MARK: - Private line

    private func privateLineRow(_ member: Member) -> some View {
        Label {
            Text("Direct line with \(member.displayName)")
                .font(.subheadline.weight(.medium))
        } icon: {
            Image(systemName: "person.wave.2.fill").foregroundStyle(Theme.warning)
        }
        .listRowBackground(Theme.warning.opacity(0.12))
    }

    // MARK: - Invite

    private var inviteSection: some View {
        Section {
            if let code = session.squad?.joinCode {
                VStack(spacing: 10) {
                    Text(code)
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .kerning(4)
                    Text("Your squad code — you chose this")
                        .font(.footnote).foregroundStyle(Theme.textDim)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)

                ShareLink(item: "Join my squad on Squadstream — code \(code)\n\nhttps://testflight.apple.com/join/fXWm1aq2") {
                    Label("Send an invite", systemImage: "square.and.arrow.up")
                }
                Button {
                    UIPasteboard.general.string = code
                    Haptics.selection()
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy code",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                Button { showJoin = true } label: {
                    Label("Switch to another code", systemImage: "arrow.right.circle")
                }
            }
        } header: {
            Text("You're the only one on")
        } footer: {
            Text("They install Squadstream, type this same code, and they're on. Whoever opens it first creates it — there's no host and no invite to accept.")
        }
    }
}

/// Entering a code is a deliberate choice from inside a working app, not the
/// price of admission.
struct SwitchSquadSheet: View {
    @EnvironmentObject private var session: SessionManager
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("742", text: $code)
                        .keyboardType(.numberPad)
                        .font(.title.monospaced())
                        .multilineTextAlignment(.center)
                        .focused($focused)
                        .onChange(of: code) { _, new in
                            code = String(new.filter(\.isNumber).prefix(8))
                        }
                        .submitLabel(.go)
                        .onSubmit {
                            guard code.count >= 3 else { return }
                            Task { await session.joinOrCreate(code: code); dismiss() }
                        }
                        .padding(.vertical, 8)
                } footer: {
                    Text("3 to 8 digits. You'll leave your current line. If nobody is on that code yet, you'll start it.")
                }
            }
            .navigationTitle("Switch code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
        .onAppear { focused = true }
    }
}
