import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var session: SessionManager
    @EnvironmentObject private var audio: AudioCoordinator
    @State private var showSettings = false
    @State private var showJoin = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let from = session.privateLineFrom {
                        PrivateLineBanner(name: from.displayName)
                    }
                    radarCard
                    statusCard
                    if !session.members.isEmpty {
                        MixerView()
                    } else {
                        emptySquad
                    }
                    if !PreferencesStore.shared.current.openMic {
                        pushToTalk
                    }
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle(session.squad?.name ?? "squad comms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Leave") { Task { await session.leave() } }
                        .foregroundStyle(Theme.muted)
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showJoin) { SwitchSquadSheet() }
        }
        .task { await audio.startListening() }
        .onDisappear { audio.stopListening() }
    }

    /// The radar is the hero. It answers the only question that matters when
    /// you walk onto a gym floor: who is here, and how far away.
    private var radarCard: some View {
        VStack(spacing: 14) {
            HStack {
                Text("LIVE RADAR").stampLabel()
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(session.proximity.isScanning ? Theme.live : Theme.textFaint)
                        .frame(width: 6, height: 6)
                    Text(session.proximity.isScanning ? "SCANNING" : "BLUETOOTH OFF")
                        .font(.system(size: 10, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(Theme.textFaint)
                }
            }

            PlateRadarView(
                contacts: session.proximity.contacts,
                names: Dictionary(uniqueKeysWithValues: session.members.map { ($0.id, $0.displayName) }),
                speakingID: session.members.first(where: { $0.isSpeaking })?.id,
                isScanning: session.proximity.isScanning
            )
            .frame(maxWidth: 300)

            RangeLoaderView(index: Binding(
                get: { session.proximity.rangeIndex },
                set: { session.proximity.rangeIndex = $0 }
            ))
        }
        .card()
    }

    private var statusCard: some View {
        VStack(spacing: 14) {
            HStack {
                Circle()
                    .fill(audio.isTransmitting ? Theme.live : Theme.hairline)
                    .frame(width: 10, height: 10)
                Text(audio.isTransmitting ? "They can hear you" : "Line open, mic quiet")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let code = session.squad?.joinCode {
                    Text(code)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            LevelMeter(db: audio.inputLevelDB)

            Text("Put your phone away. When someone talks, your music steps aside.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .card()
    }

    /// You are always in a squad, so "empty" means nobody has joined yours yet.
    /// This is where the code lives now — as something you hand out, and a way
    /// to move over to someone else's line if they already have one going.
    private var emptySquad: some View {
        VStack(spacing: 12) {
            Text("You're the only one on")
                .font(.headline)
                .foregroundStyle(Theme.text)
            Text("Send your code and they drop straight in — no setup on their end.")
                .font(.footnote)
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)

            if let code = session.squad?.joinCode {
                Text(code)
                    .font(.system(size: 30, weight: .semibold, design: .monospaced))
                    .tracking(6)
                    .foregroundStyle(Theme.text)
                    .padding(.top, 2)

                ShareLink(item: "Join my squad on squad comms — code \(code)") {
                    Text("Share code").font(.subheadline.weight(.medium))
                }
            }

            Button("Join someone else's") { showJoin = true }
                .font(.footnote)
                .foregroundStyle(Theme.textFaint)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private var pushToTalk: some View {
        Button { } label: {
            Text(audio.isTransmitting ? "Release to stop" : "Hold to talk")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(audio.isTransmitting ? Theme.live : Theme.surfaceAlt,
                            in: RoundedRectangle(cornerRadius: Theme.corner))
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in audio.pushToTalkDown() }
                .onEnded { _ in audio.pushToTalkUp() }
        )
    }
}

struct LevelMeter: View {
    let db: Float

    private var normalized: CGFloat {
        CGFloat(max(0, min(1, (db + 60) / 60)))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surfaceAlt)
                Capsule()
                    .fill(Theme.live)
                    .frame(width: geo.size.width * normalized)
                    .animation(.linear(duration: 0.08), value: normalized)
            }
        }
        .frame(height: 6)
    }
}

/// Entering a code is now an explicit choice made from inside a working app,
/// not the price of admission.
struct SwitchSquadSheet: View {
    @EnvironmentObject private var session: SessionManager
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 18) {
            Text("Join someone else's squad")
                .font(.headline)
                .foregroundStyle(Theme.text)
            Text("You'll leave your own line to do it.")
                .font(.footnote)
                .foregroundStyle(Theme.textDim)

            TextField("000000", text: $code)
                .textFieldStyle(.plain)
                .keyboardType(.numberPad)
                .font(.system(size: 36, weight: .semibold, design: .monospaced))
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
                .padding(.vertical, 10)

            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .onAppear { focused = true }
    }
}

/// An inbound direct line has to be obvious at a glance, not just audible —
/// you might be mid-set with the phone face down when the tone plays.
struct PrivateLineBanner: View {
    let name: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "person.wave.2.fill")
                .font(.system(size: 14))
            Text("\(name.uppercased()) — DIRECT LINE")
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.8)
            Spacer()
        }
        .foregroundStyle(Theme.background)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Theme.plate15, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
