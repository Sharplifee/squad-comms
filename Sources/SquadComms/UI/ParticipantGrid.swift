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

    private let columns = [GridItem(.flexible(), spacing: 11),
                           GridItem(.flexible(), spacing: 11)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 11) {
            SelfTile()
            ForEach(members) { member in
                ParticipantTile(member: member)
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
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.white)
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
    @EnvironmentObject private var session: SessionManager

    var body: some View {
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
            .foregroundStyle(muted ? Theme.muted : (speaking ? Theme.live : Theme.textFaint))
            .frame(width: 24, height: 24)
            .background(Circle().fill(Theme.background))
            .offset(x: 5, y: 5)
    }
}
