import SwiftUI

/// The main screen.
///
/// Shaped like Find My: one hero that answers "who is here", a plain list of
/// people underneath, and everything else pushed into the toolbar or Settings.
/// The previous version stacked five equally-weighted cards, which meant
/// nothing was the answer to anything — you had to read all of it to learn one
/// thing. Here the radar is the only large element on screen.
struct HomeView: View {
    @EnvironmentObject private var session: SessionManager
    @EnvironmentObject private var audio: AudioCoordinator
    @State private var showSettings = false
    @State private var showJoin = false

    var body: some View {
        NavigationStack {
            List {
                if session.privateLineFrom != nil {
                    Section { privateLineRow }
                }

                Section {
                    radar
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
                        .listRowBackground(Color.clear)
                }

                Section {
                    RangeLoaderView(index: Binding(
                        get: { session.proximity.rangeIndex },
                        set: { session.proximity.rangeIndex = $0 }
                    ))
                }

                if session.members.isEmpty {
                    inviteSection
                } else {
                    MixerView()
                }

                if !PreferencesStore.shared.current.openMic {
                    Section { pushToTalk.listRowInsets(EdgeInsets()) }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(session.squad?.name ?? "Squad")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Leave", role: .destructive) {
                        Task { await session.leave() }
                    }
                }
                // Live state belongs in the chrome, not in a card competing
                // with the radar for attention.
                ToolbarItem(placement: .status) {
                    micStatus
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showJoin) { SwitchSquadSheet() }
        }
        .task { await audio.startListening() }
        .onDisappear { audio.stopListening() }
    }

    // MARK: - Hero

    private var radar: some View {
        PlateRadarView(
            contacts: session.proximity.contacts,
            names: Dictionary(uniqueKeysWithValues: session.members.map { ($0.id, $0.displayName) }),
            speakingID: session.members.first(where: { $0.isSpeaking })?.id,
            isScanning: session.proximity.isScanning
        )
        .frame(maxWidth: .infinity)
        .frame(maxHeight: 320)
    }

    // MARK: - Status

    private var micStatus: some View {
        HStack(spacing: 6) {
            Image(systemName: audio.isTransmitting ? "waveform" : "waveform.slash")
                .font(.caption)
                .foregroundStyle(audio.isTransmitting ? Theme.live : Theme.textFaint)
                .symbolEffect(.variableColor, isActive: audio.isTransmitting)
            Text(audio.isTransmitting ? "They can hear you" : "Line open")
                .font(.caption)
                .foregroundStyle(Theme.textDim)
        }
    }

    private var privateLineRow: some View {
        Label {
            Text("Direct line with \(session.privateLineFrom?.displayName ?? "")")
                .font(.subheadline.weight(.medium))
        } icon: {
            Image(systemName: "person.wave.2.fill")
                .foregroundStyle(Theme.warning)
        }
        .listRowBackground(Theme.warning.opacity(0.12))
    }

    // MARK: - Invite

    private var inviteSection: some View {
        Section {
            if let code = session.squad?.joinCode {
                HStack {
                    Text("Your code")
                    Spacer()
                    Text(code)
                        .font(.body.monospaced())
                        .foregroundStyle(Theme.textDim)
                }
                ShareLink(item: "Join my squad on Squadstream — code \(code)") {
                    Label("Invite someone", systemImage: "square.and.arrow.up")
                }
            }
            Button {
                showJoin = true
            } label: {
                Label("Join another squad", systemImage: "arrow.right.circle")
            }
        } header: {
            Text("You're the only one on")
        } footer: {
            Text("Share your code and they drop straight in — there's nothing for them to set up.")
        }
    }

    // MARK: - Push to talk

    private var pushToTalk: some View {
        Button { } label: {
            Label(audio.isTransmitting ? "Release to stop" : "Hold to talk",
                  systemImage: audio.isTransmitting ? "mic.fill" : "mic")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .foregroundStyle(audio.isTransmitting ? Color.white : Theme.accent)
                .background(audio.isTransmitting ? Theme.live : Theme.surface)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in audio.pushToTalkDown() }
                .onEnded { _ in audio.pushToTalkUp() }
        )
    }
}

// MARK: - Join sheet

/// Entering a code is a deliberate choice made from inside a working app, not
/// the price of admission.
struct SwitchSquadSheet: View {
    @EnvironmentObject private var session: SessionManager
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("000000", text: $code)
                        .keyboardType(.numberPad)
                        .font(.title.monospaced())
                        .multilineTextAlignment(.center)
                        .focused($focused)
                        .onChange(of: code) { _, new in
                            code = String(new.filter(\.isNumber).prefix(6))
                            if code.count == 6 {
                                Task {
                                    await session.join(code: code)
                                    dismiss()
                                }
                            }
                        }
                        .padding(.vertical, 8)
                } footer: {
                    Text("You'll leave your own line to join theirs.")
                }
            }
            .navigationTitle("Join a squad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { focused = true }
    }
}
