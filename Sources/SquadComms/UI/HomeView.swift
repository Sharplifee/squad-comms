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
    @State private var showStart = false
    @State private var prefs = PreferencesStore.shared.current

    var body: some View {
        NavigationStack {
            List {
                if let from = session.privateLineFrom {
                    Section { privateLineRow(from) }
                }

                if session.squad == nil {
                    idleSection
                } else if session.members.isEmpty {
                    liveCodeSection
                } else {
                    radarSection
                    Section { ParticipantGrid(members: session.members) }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                    intercomSection
                }

                Section { MicCard() }

                if session.squad != nil { nearbySection }

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
            .sheet(isPresented: $showStart) { StartLineSheet() }
        }
        // Listening holds the microphone and takes the audio session live, so
        // it must not start merely because the app is open — that is what made
        // music sound distant the moment you launched.
        .task(id: session.squad?.id) {
            if session.squad != nil { await audio.startListening() }
            else { audio.stopListening() }
        }
        .onDisappear { audio.stopListening() }
    }

    // MARK: - Radar

    private var radarSection: some View {
        Group {
            Section {
                // List row modifiers must sit on one view, not on the branches
                // of an if/else — Group collapses the two cases into a single
                // view so the insets apply to whichever is showing.
                Group {
                    // Beyond 100 miles the rings say nothing, because everybody
                    // pins to the outer edge — so the radar hands to a map.
                    if session.proximity.rangeIndex >= 7 {
                        ContinentalView(members: session.members)
                    } else {
                        PlateRadarView(
                            contacts: session.proximity.contacts,
                            rangeIndex: session.proximity.rangeIndex,
                            names: Dictionary(uniqueKeysWithValues: session.members.map { ($0.id, $0.displayName) }),
                            speakingID: session.members.first(where: { $0.isSpeaking })?.id,
                            isScanning: session.proximity.isScanning
                        )
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 300)
                    }
                }
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

    // MARK: - Nearby

    /// Devices the radar can see, whether or not they are on your line.
    ///
    /// Distance is the useful part: it tells you if the person you are talking
    /// to is across the floor or standing behind you, which changes whether you
    /// use the app at all.
    private var nearbySection: some View {
        Section {
            if session.proximity.contacts.isEmpty {
                Text(session.proximity.isScanning
                     ? "Nothing in range yet"
                     : "Bluetooth is off")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textDim)
            } else {
                ForEach(session.proximity.contacts) { contact in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Theme.color(for: contact.normalised))
                            .frame(width: 8, height: 8)
                        Text(name(for: contact.id))
                        Spacer()
                        Text(distance(contact.metres))
                            .font(.subheadline)
                            .foregroundStyle(Theme.textDim)
                            .monospacedDigit()
                    }
                }
            }
        } header: {
            Text("Nearby")
        } footer: {
            Text("Bluetooth range. Someone can be on your line from anywhere — this is just who is physically close.")
        }
    }

    private func name(for id: UUID) -> String {
        session.members.first(where: { $0.id == id })?.displayName ?? "Unknown device"
    }

    /// Feet below ~90 m, miles above. Nobody thinks in metres on a gym floor,
    /// and nobody thinks in feet once it is a drive away.
    private func distance(_ metres: Double) -> String {
        if metres < 91 { return "\(Int((metres * 3.28084).rounded())) ft" }
        return String(format: "%.1f mi", metres / 1609.34)
    }

    // MARK: - Presence

    /// Ghost and Private sit side by side because they are the same kind of
    /// decision — who can find you — and reading them together is how you
    /// understand either one.
    private var presenceSection: some View {
        Section {
            HStack(spacing: 11) {
                presenceCard(
                    title: "GHOST MODE",
                    detail: "Hide from other radars",
                    isOn: $prefs.ghostMode
                )
                presenceCard(
                    title: "PRIVATE",
                    detail: "Code required to join",
                    isOn: $prefs.privateSession
                )
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
        }
        .onChange(of: prefs) { _, new in
            PreferencesStore.shared.update { $0 = new }
            session.applyPresence()
        }
    }

    private func presenceCard(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textDim)
            Text(detail)
                .font(.caption)
                .foregroundStyle(Theme.textFaint)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("", isOn: isOn)
                .labelsHidden()
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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

    // MARK: - Idle

    /// Nothing is open. No code exists yet, because a code is created when you
    /// start a line — showing one before that is showing a session that does
    /// not exist.
    private var idleSection: some View {
        Section {
            Button {
                showStart = true
            } label: {
                Label("Open a line", systemImage: "dot.radiowaves.left.and.right")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)

            Button {
                showJoin = true
            } label: {
                Label("Join with a code", systemImage: "arrow.right.circle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
        } footer: {
            Text("Your music is untouched until a line is open.")
        }
    }

    /// The code, once a line exists. Small — it is a reference, not the hero.
    private var liveCodeSection: some View {
        Section {
            if let code = session.squad?.joinCode {
                HStack {
                    Text("Code")
                    Spacer()
                    Text(code)
                        .font(.body.monospaced())
                        .foregroundStyle(Theme.textDim)
                }
                ShareLink(item: "Join my squad on Squadstream — code \(code)") {
                    Label("Share code", systemImage: "square.and.arrow.up")
                }
            }
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

/// Starting a line. You choose the code here — it does not exist until now.
struct StartLineSheet: View {
    @EnvironmentObject private var session: SessionManager
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var working = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("Pick a code for your line")
                    .font(.headline)
                Text("Anything from 3 to 8 digits. Whoever types the same one lands with you.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                TextField("742", text: $code)
                    .keyboardType(.numberPad)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .kerning(5)
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .onChange(of: code) { _, new in
                        code = String(new.filter(\.isNumber).prefix(8))
                    }

                Button {
                    working = true
                    Task {
                        await session.joinOrCreate(code: code)
                        working = false
                        dismiss()
                    }
                } label: {
                    Group {
                        if working { ProgressView().tint(.white) }
                        else { Text("Open the line").font(.headline) }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(code.count < 3 || working)
                .padding(.horizontal, 24)

                Spacer()
            }
            .padding(.top, 26)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
        .onAppear { focused = true }
    }
}
