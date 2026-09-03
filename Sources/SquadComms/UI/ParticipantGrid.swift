import SwiftUI

/// The squad as tiles.
///
/// A two-column grid of faces reads at arm's length across a gym floor in a way
/// a list of rows does not. Rounded squares rather than circles, because circles
/// at this size read as chat avatars and this is not a chat.
///
/// Tap a tile to mute that person. The border pulses while they speak, which is
/// the one thing you want to catch out of the corner of your eye.
struct ParticipantGrid: View {
    let members: [Member]
    @EnvironmentObject private var session: SessionManager
    @State private var expanded: UUID?

    private let columns = [GridItem(.flexible(), spacing: 11),
                           GridItem(.flexible(), spacing: 11)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 11) {
            SelfTile()
            ForEach(members) { member in
                ParticipantTile(member: member, expanded: $expanded)
            }
        }
    }
}

private struct SelfTile: View {
    @EnvironmentObject private var session: SessionManager
    @EnvironmentObject private var audio: AudioCoordinator

    var body: some View {
        VStack(spacing: 10) {
            avatar(initials(PreferencesStore.shared.current.displayName),
                   speaking: audio.isTransmitting,
                   muted: session.selfMuted)
            HStack(spacing: 6) {
                Text(PreferencesStore.shared.current.displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text("YOU")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(audio.isTransmitting ? Theme.live : .clear, lineWidth: 2)
        )
        .animation(.easeInOut(duration: 0.15), value: audio.isTransmitting)
    }
}

private struct ParticipantTile: View {
    let member: Member
    @Binding var expanded: UUID?
    @EnvironmentObject private var session: SessionManager

    private var isExpanded: Bool { expanded == member.id }

    var body: some View {
        VStack(spacing: 0) {
            tile
            // Long press opens this person's controls in place, so adjusting
            // one person mid-set does not mean leaving the screen showing
            // everyone.
            if isExpanded { controls }
        }
        .animation(.snappy(duration: 0.22), value: isExpanded)
        .onLongPressGesture(minimumDuration: 0.35) {
            expanded = isExpanded ? nil : member.id
            Haptics.impact(.medium)
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "speaker.fill").font(.caption2).foregroundStyle(Theme.textFaint)
                Slider(
                    value: Binding(
                        get: { member.volume },
                        set: { session.setVolume($0, for: member) }
                    ),
                    in: 0...1
                )
                .disabled(member.isMutedByMe)
                Text("\(Int(member.volume * 100))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.textFaint)
                    .frame(width: 24, alignment: .trailing)
            }

            Toggle("I hear them", isOn: Binding(
                get: { !member.isMutedByMe },
                set: { session.setMuted(!$0, for: member) }
            ))
            .font(.caption)

            Toggle("They hear me", isOn: Binding(
                get: { !member.isMutedToThem },
                set: { session.setMutedToThem(!$0, for: member) }
            ))
            .font(.caption)
        }
        .padding(12)
        .background(Theme.surfaceAlt, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.top, 6)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var tile: some View {
        Button {
            session.setMuted(!member.isMutedByMe, for: member)
            Haptics.selection()
        } label: {
            VStack(spacing: 10) {
                avatar(initials(member.displayName),
                       speaking: member.isSpeaking && !member.isMutedByMe,
                       muted: member.isMutedByMe)
                Text(member.displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(member.isMutedByMe ? Theme.textDim : Theme.text)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(member.isSpeaking && !member.isMutedByMe ? Theme.live : .clear,
                                  lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: member.isSpeaking)
    }
}

private func initials(_ name: String) -> String {
    let parts = name.split(separator: " ")
    let letters = parts.prefix(2).compactMap { $0.first }
    return letters.isEmpty ? "?" : String(letters).uppercased()
}

@ViewBuilder
private func avatar(_ text: String, speaking: Bool, muted: Bool) -> some View {
    ZStack(alignment: .bottomTrailing) {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(speaking ? Theme.live.opacity(0.18) : Theme.surfaceAlt)
            .frame(width: 66, height: 66)
            .overlay(
                Text(text)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(muted ? Theme.textDim : Theme.text)
            )

        Image(systemName: muted ? "mic.slash.fill" : (speaking ? "mic.fill" : "mic"))
            .font(.system(size: 11))
            .foregroundStyle(muted ? Theme.danger : (speaking ? Theme.signal : Theme.dim))
            .frame(width: 24, height: 24)
            .background(Circle().fill(Theme.background))
            .offset(x: 5, y: 5)
    }
}
