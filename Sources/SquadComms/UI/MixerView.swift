import SwiftUI

/// Per-listener mixing. Everyone controls their own experience — you can
/// quietly turn someone down without it being a whole thing.
struct MixerView: View {
    @EnvironmentObject private var session: SessionManager

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Who you're hearing")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button(allMuted ? "Unmute everyone" : "Mute everyone") {
                    session.muteAll(!allMuted)
                }
                .font(.footnote)
                .foregroundStyle(Theme.accent)
            }
            .padding(.bottom, 14)

            ForEach(session.members) { member in
                MemberRow(member: member)
                if member.id != session.members.last?.id {
                    Divider().overlay(Theme.hairline).padding(.vertical, 12)
                }
            }
        }
        .card()
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
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(member.isSpeaking && !member.isMutedByMe ? Theme.live : Theme.hairline)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 1) {
                    Text(member.displayName)
                        .font(.body.weight(.medium))
                    if isPrivate || theyOpenedPrivate {
                        Text(isPrivate ? "DIRECT LINE — HOLDING" : "DIRECT LINE TO YOU")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(0.7)
                            .foregroundStyle(Theme.warning)
                    }
                }

                if member.nearby && !isPrivate && !theyOpenedPrivate {
                    Text("nearby")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.surfaceAlt, in: Capsule())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    session.setMuted(!member.isMutedByMe, for: member)
                } label: {
                    Image(systemName: member.isMutedByMe ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundStyle(member.isMutedByMe ? Theme.muted : .secondary)
                }
                .buttonStyle(.plain)
            }
            // Hold a name to talk to that person only. A hold rather than a
            // toggle on purpose: a private channel you can forget you left
            // open is how you say something to one person while believing the
            // whole squad can hear it.
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.28, maximumDistance: 30) {
            } onPressingChanged: { pressing in
                holding = pressing
                if pressing { session.beginPrivateLine(to: member) }
                else        { session.endPrivateLine() }
            }

            HStack(spacing: 10) {
                Image(systemName: "speaker.fill").font(.caption2).foregroundStyle(.tertiary)
                Slider(
                    value: Binding(
                        get: { member.volume },
                        set: { session.setVolume($0, for: member) }
                    ),
                    in: 0...1
                )
                .tint(Theme.accent)
                .disabled(member.isMutedByMe)
                Image(systemName: "speaker.wave.3.fill").font(.caption2).foregroundStyle(.tertiary)
            }
            .opacity(member.isMutedByMe ? 0.35 : 1)
        }
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isPrivate || theyOpenedPrivate ? Theme.warning.opacity(0.12) : .clear)
        )
        .scaleEffect(holding ? 0.985 : 1)
        .animation(.easeOut(duration: 0.12), value: holding)
        .animation(.easeInOut(duration: 0.18), value: isPrivate)
        .animation(.easeInOut(duration: 0.18), value: theyOpenedPrivate)
    }
}
