import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var session: SessionManager
    @EnvironmentObject private var audio: AudioCoordinator
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
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

    private var emptySquad: some View {
        VStack(spacing: 10) {
            Text("Nobody else is on yet")
                .font(.headline)
            Text("Share your code and they'll drop straight in.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let code = session.squad?.joinCode {
                ShareLink(item: "Join my squad on squad comms — code \(code)") {
                    Text("Share the code").font(.subheadline.weight(.medium))
                }
                .padding(.top, 4)
            }
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
