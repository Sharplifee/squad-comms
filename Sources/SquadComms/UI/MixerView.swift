import SwiftUI

/// Who you're hearing, and how loud.
///
/// A plain grouped-list section: one row per person, name and state on the
/// left, a volume slider beneath. Muting is a swipe action rather than a
/// permanent button, because muting someone is occasional and a button for it
/// on every row adds visual weight to the thing you do least.
///
/// Holding a name opens a direct line to that person only.
struct MixerView: View {
    @EnvironmentObject private var session: SessionManager

    var body: some View {
        Section {
            ForEach(session.members) { member in
                MemberRow(member: member)
            }
        } header: {
            HStack {
                Text("Squad")
                Spacer()
                Button(allMuted ? "Unmute all" : "Mute all") {
                    session.muteAll(!allMuted)
                    Haptics.selection()
                }
                .font(.footnote)
                .textCase(nil)
            }
        } footer: {
            Text("Hold a name to talk to that person only.")
        }
    }

    private var allMuted: Bool {
        !session.members.isEmpty && session.members.allSatisfy(\.isMutedByMe)
    }
}

struct MemberRow: View {
    let member: Member
    @EnvironmentObject private var session: SessionManager
    @State private var holding = false

    private var isPrivate: Bool { session.privateLineTo?.id == member.id }
    private var theyOpenedPrivate: Bool { session.privateLineFrom?.id == member.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                // Presence, as a single glyph rather than a coloured dot plus a
                // badge plus a label. SF Symbols carry the state on their own.
                Image(systemName: symbol)
                    .font(.body)
                    .foregroundStyle(symbolColour)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(member.displayName)
                        .foregroundStyle(member.isMutedByMe ? Theme.textDim : Theme.text)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(isPrivate || theyOpenedPrivate ? Theme.warning : Theme.textDim)
                    }
                }

                Spacer()

                if member.nearby && !isPrivate && !theyOpenedPrivate {
                    Text("Nearby")
                        .font(.caption2)
                        .foregroundStyle(Theme.textFaint)
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.textFaint)
                Slider(
                    value: Binding(
                        get: { member.volume },
                        set: { session.setVolume($0, for: member) }
                    ),
                    in: 0...1
                )
                .disabled(member.isMutedByMe)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.textFaint)
            }
            .opacity(member.isMutedByMe ? 0.4 : 1)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        // onPressingChanged fires on touch-down rather than after the minimum
        // duration, so binding the line to it opened a private channel on every
        // stray tap and every scroll that began on a row.
        .gesture(
            LongPressGesture(minimumDuration: 0.28)
                .onEnded { _ in
                    holding = true
                    session.beginPrivateLine(to: member)
                }
                .sequenced(before: DragGesture(minimumDistance: 0))
                .onEnded { _ in
                    holding = false
                    session.endPrivateLine()
                }
        )
        .onDisappear {
            if holding { holding = false; session.endPrivateLine() }
        }
        .listRowBackground(
            isPrivate || theyOpenedPrivate
                ? Theme.warning.opacity(0.12)
                : Color(.secondarySystemGroupedBackground)
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: member.isMutedByMe ? .cancel : .destructive) {
                session.setMuted(!member.isMutedByMe, for: member)
                Haptics.selection()
            } label: {
                Label(member.isMutedByMe ? "Unmute" : "Mute",
                      systemImage: member.isMutedByMe ? "speaker.wave.2" : "speaker.slash")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isPrivate)
        .animation(.easeInOut(duration: 0.2), value: theyOpenedPrivate)
    }

    private var symbol: String {
        if isPrivate || theyOpenedPrivate { return "person.wave.2.fill" }
        if member.isMutedByMe             { return "speaker.slash.fill" }
        if member.isSpeaking              { return "waveform" }
        return "person.fill"
    }

    private var symbolColour: Color {
        if isPrivate || theyOpenedPrivate { return Theme.warning }
        if member.isMutedByMe             { return Theme.muted }
        if member.isSpeaking              { return Theme.live }
        return Theme.textFaint
    }

    private var detail: String? {
        if isPrivate         { return "Direct line — holding" }
        if theyOpenedPrivate { return "Direct line to you" }
        if member.isMutedByMe { return "Muted" }
        if member.isSpeaking  { return "Speaking" }
        return nil
    }
}
