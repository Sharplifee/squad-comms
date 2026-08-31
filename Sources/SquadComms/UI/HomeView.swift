import SwiftUI

/// The main screen.
///
/// Shaped like Find My: one hero that answers "who is here", a plain list of
/// people underneath, and everything else pushed into the toolbar or Settings.
/// The previous version stacked five equally-weighted cards, which meant
/// nothing was the answer to anything — you had to read all of it to learn one
/// thing. Here the radar is the only large element on screen.
struct HomeView: View {
    @ObservedObject var focus: FocusModeController
    @EnvironmentObject private var session: SessionManager
    @EnvironmentObject private var audio: AudioCoordinator
    @State private var showSettings = false
    @State private var showJoin = false
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                if session.privateLineFrom != nil {
                    Section { privateLineRow }
                }

                Section { lineStatus }

                if session.members.isEmpty {
                    inviteSection
                } else {
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
                    } footer: {
                        Text("Bluetooth range only — it doesn't affect who can hear you.")
                    }
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
                    Menu {
                        FocusButton(focus: focus)
                        Button {
                            session.muteAll(!allMuted)
                        } label: {
                            Label(allMuted ? "Unmute everyone" : "Mute everyone",
                                  systemImage: allMuted ? "speaker.wave.2" : "speaker.slash")
                        }
                        Divider()
                        Button { showSettings = true } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Leave", role: .destructive) {
                        Task { await session.leave() }
                    }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showJoin) { SwitchSquadSheet() }
        }
        .task { await audio.startListening() }
        .onDisappear { audio.stopListening() }
    }

    private var allMuted: Bool {
        !session.members.isEmpty && session.members.allSatisfy(\.isMutedByMe)
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

    /// States the actual condition of the line in a sentence. The previous
    /// version put this in a floating toolbar pill that rendered on top of the
    /// list content and read "Li…" when truncated.
    private var lineStatus: some View {
        HStack(spacing: 12) {
            Image(systemName: audio.isTransmitting ? "waveform" : "waveform.slash")
                .font(.title3)
                .foregroundStyle(audio.isTransmitting ? Theme.live : Theme.textFaint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(audio.isTransmitting ? "They can hear you" : "Line open")
                    .font(.body)
                Text(audio.isTransmitting
                     ? "Your voice is going through now."
                     : "Put your phone away — talking opens the mic on its own.")
                    .font(.caption)
                    .foregroundStyle(Theme.textDim)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

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
                // The code is the whole product surface when you are alone, so
                // it gets the space rather than sitting as a grey trailing
                // label on a row.
                VStack(spacing: 10) {
                    Text(code)
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .kerning(4)
                    Text("Your squad code")
                        .font(.footnote)
                        .foregroundStyle(Theme.textDim)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)

                ShareLink(
                    item: "Join my squad on Squadstream — code \(code)\n\nhttps://testflight.apple.com/join/fXWm1aq2"
                ) {
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

                Button {
                    showJoin = true
                } label: {
                    Label("Enter someone else's code", systemImage: "arrow.right.circle")
                }
            }
        } footer: {
            Text("They install Squadstream, type this code, and they're on. Nothing else to set up.")
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
