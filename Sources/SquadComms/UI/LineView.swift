import SwiftUI

/// The Line tab.
///
/// The screen answers a different question depending on whether a line is
/// open, so it is ordered differently in each case rather than being one
/// layout with things hidden.
///
/// **Closed**, the only question is whether to open a line and with whom, so:
/// state, the action, then who is nearby. There is deliberately no level meter
/// — there is nothing to meter when nothing is transmitting, and a meter
/// bouncing on a closed line is noise pretending to be information.
///
/// **Open**, the question flips to who is talking, so the ribbon comes first
/// and the code sinks to the bottom where you only look on purpose.
struct LineView: View {
    @ObservedObject var focus: FocusModeController
    @EnvironmentObject private var session: SessionManager
    @EnvironmentObject private var audio: AudioCoordinator
    @EnvironmentObject private var toasts: ToastCenter

    @State private var showStart = false
    @State private var showJoin = false
    @State private var showEndOptions = false
    @StateObject private var saved = SavedSquadStore.shared
    @State private var prefs = PreferencesStore.shared.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                masthead
                if session.squad == nil { closed } else { open }
            }
            .padding(.bottom, 24)
        }
        .background(Theme.base)
        .sheet(isPresented: $showStart) { StartLineSheet() }
        .sheet(isPresented: $showJoin)  { SwitchSquadSheet() }
        .confirmationDialog("End this session?", isPresented: $showEndOptions, titleVisibility: .visible) {
            Button("End for everyone", role: .destructive) { Task { await session.endForEveryone() } }
            Button("Just leave") { Task { await session.leave() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You can step out on your own, or close the line for everyone on it.")
        }
        .task(id: session.squad?.id) {
            if session.squad != nil { await audio.startListening() } else { audio.stopListening() }
        }
    }

    // MARK: - Masthead

    private var masthead: some View {
        HStack {
            Text("SQUAD COMMS")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .tracking(1.3)
                .foregroundStyle(Theme.dim)
            Spacer()
            if session.squad != nil, let start = session.sessionStart {
                Text(elapsed(since: start))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            } else {
                // The real output device, not a generic label — knowing you are
                // about to broadcast through the room speaker matters.
                HStack(spacing: 6) {
                    Circle()
                        .fill(audio.audioSession.usingHeadphones ? Theme.signal : Theme.danger)
                        .frame(width: 6, height: 6)
                    Text(audio.audioSession.routeName)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 4)
        .padding(.bottom, 18)
    }

    // MARK: - Closed

    private var closed: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("The line is closed")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .padding(.horizontal, 22)
            Text("Open one and your squad can just talk. Your music keeps playing.")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 22)
                .padding(.top, 9)

            Button { showStart = true } label: {
                Text("Open the line")
                    .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 19)
            }
            .background(Theme.text, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(Theme.base)
            .padding(.horizontal, 22)
            .padding(.top, 20)

            Button("Have a code? Join instead") { showJoin = true }
                .font(.system(size: 13.5, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)

            if !saved.squads.isEmpty { savedSquads }

            NearbyPanel(
                contacts: session.proximity.contacts,
                names: [:],
                speakingID: nil,
                isScanning: session.proximity.isScanning,
                rangeIndex: Binding(get: { session.proximity.rangeIndex },
                                    set: { session.proximity.rangeIndex = $0 })
            )
            .padding(.horizontal, 22)
            .padding(.top, 26)

            micCheck
        }
    }

    private var savedSquads: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Your squads")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.dim)
                .padding(.horizontal, 24)
                .padding(.top, 26)

            ForEach(saved.squads) { squad in
                Button {
                    Task { await session.join(code: squad.code) }
                } label: {
                    HStack(spacing: 13) {
                        Text(squad.code)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 52, height: 40)
                            .background(Theme.raised,
                                        in: RoundedRectangle(cornerRadius: Theme.avatarCorner, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(squad.name)
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.text)
                            Text(squad.subtitle)
                                .font(.system(size: 12.5, design: .rounded))
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                    }
                    .padding(13)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 22)
            }
        }
    }

    /// One line stating the threshold, tapping through to the control. Not a
    /// meter — there is nothing to meter yet.
    private var micCheck: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("You trigger the line at \(Int(prefs.vadOnsetDB)) dB")
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                Text("Tap to adjust how loud you need to be")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Theme.line, lineWidth: 1))
        .padding(.horizontal, 22)
        .padding(.top, 16)
    }

    // MARK: - Open

    private var open: some View {
        VStack(alignment: .leading, spacing: 0) {
            headline
                .padding(.horizontal, 22)

            LiveRibbon(members: session.members,
                       selfSpeaking: audio.isTransmitting,
                       level: audio.inputLevelDB)
                .padding(.horizontal, 22)
                .padding(.top, 18)

            micControl
            volume

            codeRow
            Button { showEndOptions = true } label: {
                Text("Leave the line")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .foregroundStyle(Theme.danger)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.danger.opacity(0.32), lineWidth: 1))
            .padding(.horizontal, 22)
            .padding(.top, 10)
        }
    }

    private var headline: some View {
        Group {
            if audio.isTransmitting {
                Text("You're on")
                    .foregroundStyle(Theme.signal)
            } else if let speaker = session.members.first(where: { $0.isSpeaking && !$0.isMutedByMe }) {
                Text("\(speaker.displayName) is talking")
            } else if session.members.isEmpty {
                Text("Waiting for your squad")
            } else {
                Text("Line open")
            }
        }
        .font(.system(size: 32, weight: .bold, design: .rounded))
    }

    private var micControl: some View {
        Button {
            session.setSelfMuted(!session.selfMuted)
            Haptics.impact(.medium)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: session.selfMuted ? "mic.slash.fill" : "mic.fill")
                Text(session.selfMuted ? "Microphone muted" : "Microphone on")
            }
            .font(.system(size: 16.5, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 21)
        }
        .background(audio.isTransmitting ? Theme.signal : Theme.surface,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .foregroundStyle(audio.isTransmitting ? Theme.base
                         : (session.selfMuted ? Theme.danger : Theme.text))
        .padding(.horizontal, 22)
        .padding(.top, 20)
    }

    private var volume: some View {
        VStack(spacing: 9) {
            HStack {
                Text("Squad volume")
                    .font(.system(size: 14.5, weight: .medium, design: .rounded))
                Spacer()
                Text("\(Int(prefs.intercomVolume * 100))%")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }
            Slider(value: $prefs.intercomVolume, in: 0...1)
                .tint(Theme.text)
        }
        .padding(17)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .onChange(of: prefs.intercomVolume) { _, _ in
            PreferencesStore.shared.update { $0 = prefs }
            session.applyPreferences()
        }
    }

    private var codeRow: some View {
        HStack(spacing: 10) {
            Text(session.squad?.joinCode ?? "")
                .font(.system(size: 13, design: .monospaced))
                .tracking(3)
            Spacer()
            Button("Copy") {
                UIPasteboard.general.string = session.squad?.joinCode
                toasts.show("Code copied")
            }
            .font(.system(size: 12.5, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.muted)
            if let code = session.squad?.joinCode {
                ShareLink(item: "Join my squad on Squadstream — code \(code)") {
                    Text("Share")
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
    }

    private func elapsed(since date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
