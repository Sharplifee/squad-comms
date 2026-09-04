import SwiftUI

/// The Line tab.
///
/// Two screens in one, because the question changes completely the moment a
/// line is open. Closed, the only thing you want to know is whether to open
/// one and with whom. Open, it flips to who is talking — so the layout flips
/// with it rather than showing the same components in the same order.
struct LineView: View {
    @ObservedObject var focus: FocusModeController
    @EnvironmentObject private var session: SessionManager
    @EnvironmentObject private var audio: AudioCoordinator
    @EnvironmentObject private var toasts: ToastCenter
    @StateObject private var saved = SavedSquadStore.shared
    /// Watched rather than polled, so the banner appears the moment the
    /// network drops instead of when something fails.

    @State private var showStart = false
    @State private var showJoin = false
    @State private var showEndOptions = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    masthead
                    // One banner system. AppConditions already watches the
                    // network, the microphone and Bluetooth together, so the
                    // two hand-rolled banners above it were saying the same
                    // things from a second source of truth.
                    ConditionBanners()
                    .padding(.horizontal, 22)
                    .padding(.bottom, 14)
                    if session.squad == nil { closed } else { open }
                }
            }
            .background(Theme.base)
        .onAppear { AppConditions.shared.startWatching() }
        .onDisappear { AppConditions.shared.stopWatching() }
            .navigationBarHidden(true)
            .sheet(isPresented: $showStart) { StartLineSheet() }
            .sheet(isPresented: $showJoin) { SwitchSquadSheet() }
            .confirmationDialog("End this session?", isPresented: $showEndOptions,
                                titleVisibility: .visible) {
                // Only offered to whoever opened the line. Anyone joining your
                // gym line could otherwise shut it down for the whole squad.
                if session.isCreator {
                    Button("End for everyone", role: .destructive) {
                        Task { await session.endForEveryone() }
                    }
                }
                Button("Just leave") { Task { await session.leave() } }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(session.isCreator
                     ? "You can step out on your own, or close the line for everyone on it."
                     : "The line stays open for everyone else.")
            }
        }
        .task(id: session.squad?.id) {
            if session.squad != nil { await audio.startListening() } else { audio.stopListening() }
        }
    }

    // MARK: - Masthead

    private var masthead: some View {
        HStack {
            Text("SQUAD COMMS")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(Theme.textFaint)
            Spacer()
            if let started = session.sessionStart {
                Text(elapsed(since: started))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textDim)
                    .padding(.trailing, 10)
            }
            // The real output device, not a generic label. On a gym floor the
            // difference between AirPods and the speaker is whether the room
            // hears your squad.
            HStack(spacing: 6) {
                Circle()
                    .fill(audio.audioSession.usingHeadphones ? Theme.signal : Theme.danger)
                    .frame(width: 6, height: 6)
                Text(audio.audioSession.routeName)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 4)
        .padding(.bottom, 18)
    }

    /// Stated up front rather than discovered by tapping Open the line and
    /// waiting ten seconds for a timeout.
    /// Without the microphone the app cannot do the one thing it exists for,
    /// and the failure is silent — so it has to be stated, with the fix one
    /// tap away.
    // MARK: - Closed

    private var closed: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("The line is closed")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text("Open one and your squad can just talk. Your music keeps playing.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.textDim)
                .padding(.top, 9)

            Button { showStart = true } label: {
                Text("Open the line")
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 19)
            }
            .background(Theme.text, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(Theme.base)
            .padding(.top, 20)

            Button("Have a code? Join instead") { showJoin = true }
                .font(.system(.footnote, design: .rounded, weight: .medium))
                .foregroundStyle(Theme.textDim)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)

            if !saved.squads.isEmpty { savedPanel }
            nearbyPanel
            micCheck
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 30)
    }

    /// Radar and the people list as ONE card — picture on top of names, a
    /// single object. They were two cards driving one value, with the range
    /// control duplicated in both headers.
    private var nearbyPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Nearby")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Spacer()
                RangeLoaderView(index: Binding(
                    get: { session.proximity.rangeIndex },
                    set: { session.proximity.rangeIndex = $0 }
                ))
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 6)

            PlateRadarView(
                contacts: session.proximity.contacts,
                rangeIndex: session.proximity.rangeIndex,
                names: Dictionary(uniqueKeysWithValues:
                    session.members.map { ($0.id, $0.displayName) }),
                speakingID: session.members.first(where: { $0.isSpeaking })?.id,
                isScanning: session.proximity.isScanning
            )
            .frame(height: 126)
            .padding(.horizontal, 16)

            Divider().overlay(Theme.line).padding(.top, 6)

            if session.proximity.contacts.isEmpty {
                Text(session.proximity.isScanning
                     ? "Nobody nearby with the app."
                     : "Bluetooth is off, so nobody can be seen nearby.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Theme.textDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
            } else {
                ForEach(session.proximity.contacts) { contact in
                    HStack(spacing: 13) {
                        Circle().fill(Theme.raised).frame(width: 40, height: 40)
                        Text("Someone nearby")
                            .font(.system(.subheadline, design: .rounded))
                        Spacer()
                        Text(distance(contact.metres))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Theme.textDim)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 13)
                    if contact.id != session.proximity.contacts.last?.id {
                        Divider().overlay(Theme.line)
                    }
                }
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.top, 26)
    }

    private var savedPanel: some View {
        VStack(spacing: 0) {
            ForEach(saved.squads) { squad in
                Button {
                    Task { await session.join(code: squad.code) }
                } label: {
                    HStack(spacing: 13) {
                        Text(squad.code)
                            .font(.system(.footnote, design: .monospaced, weight: .semibold))
                            .foregroundStyle(Theme.textDim)
                            .frame(width: 52, height: 40)
                            .background(Theme.raised,
                                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(squad.name)
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                                .foregroundStyle(Theme.text)
                            Text(squad.subtitle)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Theme.textDim)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(Theme.textFaint)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 13)
                }
                if squad.id != saved.squads.last?.id { Divider().overlay(Theme.line) }
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.top, 26)
    }

    /// No level meter here — there is nothing to meter when the line is
    /// closed. Just the number, and a way through to change it.
    private var micCheck: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("You trigger the line at \(Int(PreferencesStore.shared.current.vadOnsetDB)) dB")
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                Text("Tap to change how loud you need to be")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textDim)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textFaint)
        }
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line))
        .padding(.top, 16)
    }

    // MARK: - Open

    private var open: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(headline)
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .foregroundStyle(audio.isTransmitting ? Theme.signal : Theme.text)

            Ribbon(members: session.members,
                   selfName: PreferencesStore.shared.current.displayName,
                   selfSpeaking: audio.isTransmitting,
                   level: normalisedLevel)
                .padding(.top, 18)

            micControl
            volume
            codeRow

            // Focus had a controller and a full-screen overlay but nothing
            // that could start it — the entire feature was unreachable.
            Menu {
                ForEach(FocusModeController.durations, id: \.self) { seconds in
                    Button("\(seconds) seconds") { focus.begin(seconds: seconds) }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "moon")
                    Text("Focus — mute the squad briefly")
                }
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(Theme.text)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)

            Button { showEndOptions = true } label: {
                Text("Leave the line")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .foregroundStyle(Theme.danger)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.danger.opacity(0.32)))
            .padding(.top, 22)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 30)
    }

    private var headline: String {
        if session.isReconnecting { return "Reconnecting" }
        if audio.isTransmitting { return "You're on" }
        let talking = session.members.filter { $0.isSpeaking && !$0.isMutedByMe }
        if talking.count == 1 { return "\(talking[0].displayName) is talking" }
        if talking.count > 1  { return "\(talking.count) people talking" }
        return session.members.isEmpty ? "Waiting for your squad" : "Nobody's talking"
    }

    /// The biggest target on the screen, because it is the one thing you reach
    /// for without looking.
    /// With open mic off there was previously no way to transmit at all — the
    /// mic button only toggled mute, and push-to-talk had no control anywhere.
    @ViewBuilder
    private var micControl: some View {
        if PreferencesStore.shared.current.openMic { openMicButton } else { pushToTalkButton }
    }

    private var pushToTalkButton: some View {
        Text(audio.isTransmitting ? "Release to stop" : "Hold to talk")
            .font(.system(.callout, design: .rounded, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 21)
            .background(audio.isTransmitting ? Theme.signal : Theme.surface,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .foregroundStyle(audio.isTransmitting ? Theme.base : Theme.text)
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !audio.isTransmitting else { return }
                        audio.pushToTalkDown()
                        Haptics.impact(.medium)
                    }
                    .onEnded { _ in audio.pushToTalkUp() }
            )
    }

    private var openMicButton: some View {
        Button {
            session.setSelfMuted(!session.selfMuted)
            Haptics.impact(.medium)
        } label: {
            HStack(spacing: 11) {
                Image(systemName: session.selfMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(.title3))
                Text(session.selfMuted ? "Microphone off" : "Microphone on")
                    .font(.system(.callout, design: .rounded, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
        }
        .background(session.selfMuted ? Theme.surface : Theme.signal,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .foregroundStyle(session.selfMuted ? Theme.text : Theme.base)
        .padding(.top, 18)
    }

    private var volume: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Squad volume")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                Spacer()
                Text("\(Int(PreferencesStore.shared.current.intercomVolume * 100))%")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Theme.textDim)
            }
            Slider(value: Binding(
                get: { PreferencesStore.shared.current.intercomVolume },
                set: { value in
                    PreferencesStore.shared.update { $0.intercomVolume = value }
                    session.applyPreferences()
                }
            ), in: 0...1)
            .tint(Theme.text)
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.top, 12)
    }

    /// At the bottom, because you only look for it on purpose.
    private var codeRow: some View {
        HStack(spacing: 10) {
            Text(session.squad?.joinCode ?? "")
                .font(.system(.subheadline, design: .monospaced, weight: .medium))
                .tracking(3)
            Spacer()
            Button("Copy") {
                UIPasteboard.general.string = session.squad?.joinCode
                toasts.show("Code copied")
            }
            .font(.system(.footnote, design: .rounded, weight: .medium))
            .foregroundStyle(Theme.textDim)
            if let code = session.squad?.joinCode {
                ShareLink(item: "Join my squad on Squadstream — code \(code)") {
                    Text("Share")
                        .font(.system(.footnote, design: .rounded, weight: .medium))
                        .foregroundStyle(Theme.textDim)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 20)
    }

    // MARK: - Helpers

    private var normalisedLevel: Double {
        session.selfMuted ? 0 : min(max(Double(audio.inputLevelDB + 60) / 60, 0), 1)
    }

    private func elapsed(since date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func distance(_ metres: Double) -> String {
        metres < 91 ? "\(Int((metres * 3.28084).rounded())) ft"
                    : String(format: "%.1f mi", metres / 1609.34)
    }
}
