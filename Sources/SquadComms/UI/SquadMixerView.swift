import SwiftUI

/// Per-person controls: who is on, how loud they are, and a direct line.
///
/// Everything is on one row and reachable with a thumb. The volume slider is
/// always visible rather than hidden behind a tap, because adjusting somebody
/// mid-set is the single most common thing anyone does in this app and it
/// should never cost a navigation step.
///
/// Holding a name opens a private line to that person only. It is a hold and
/// not a toggle on purpose: a private channel you can forget you left open is
/// how you say something to one person believing the whole squad can hear.
struct SquadMixerView: View {

    @EnvironmentObject private var session: SessionManager

    var body: some View {
        VStack(spacing: 0) {
            header

            if session.members.isEmpty {
                Text("Nobody else is on yet")
                    .font(.footnote)
                    .foregroundStyle(Theme.textFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)
            } else {
                ForEach(session.members) { member in
                    MemberRow(member: member)
                    if member.id != session.members.last?.id {
                        Divider().overlay(Theme.hairline)
                    }
                }
            }
        }
        .card()
    }

    private var header: some View {
        HStack {
            Text("SQUAD").stampLabel()
            Spacer()
            Button {
                let anyoneAudible = session.members.contains { !$0.isMutedByMe }
                session.muteAll(anyoneAudible)
                Haptics.selection()
            } label: {
                Text(session.members.contains { !$0.isMutedByMe } ? "MUTE ALL" : "UNMUTE ALL")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(Theme.textDim)
            }
        }
        .padding(.bottom, 4)
    }
}

// MARK: - Row

private struct MemberRow: View {
    let member: Member
    @EnvironmentObject private var session: SessionManager
    @State private var holding = false

    private var isPrivate: Bool { session.privateLineTo?.id == member.id }
    private var theyOpenedPrivate: Bool { session.privateLineFrom?.id == member.id }

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 11) {
                // Presence spine, coloured by distance band so the roster and
                // the radar agree without repeating each other.
                RoundedRectangle(cornerRadius: 2)
                    .fill(spineColour)
                    .frame(width: 3, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(member.displayName.uppercased())
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(member.isMutedByMe ? Theme.textFaint : Theme.text)
                    Text(statusLine)
                        .font(.system(size: 10, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(statusColour)
                }

                Spacer()

                Button {
                    session.setMuted(!member.isMutedByMe, for: member)
                    Haptics.selection()
                } label: {
                    Image(systemName: member.isMutedByMe ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(member.isMutedByMe ? Theme.plate25 : Theme.textDim)
                        .frame(width: 40, height: 34)
                }
                .buttonStyle(.plain)
            }
            // Hold anywhere on the name row to open the direct line.
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.28, maximumDistance: 30) {
                // fires when the press is recognised
            } onPressingChanged: { pressing in
                holding = pressing
                if pressing { session.beginPrivateLine(to: member) }
                else        { session.endPrivateLine() }
            }

            HStack(spacing: 9) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textFaint)
                Slider(
                    value: Binding(
                        get: { member.volume },
                        set: { session.setVolume($0, for: member) }
                    ),
                    in: 0...1
                )
                .tint(member.isMutedByMe ? Theme.textFaint : Theme.accent)
                .disabled(member.isMutedByMe)
                Text("\(Int(member.volume * 100))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
                    .frame(width: 26, alignment: .trailing)
            }
        }
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isPrivate || theyOpenedPrivate ? Theme.plate15.opacity(0.13) : .clear)
        )
        .overlay(alignment: .leading) {
            if isPrivate || theyOpenedPrivate {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.plate15)
                    .frame(width: 3)
            }
        }
        .scaleEffect(holding ? 0.985 : 1)
        .animation(.easeOut(duration: 0.12), value: holding)
        .animation(.easeInOut(duration: 0.18), value: isPrivate)
        .animation(.easeInOut(duration: 0.18), value: theyOpenedPrivate)
    }

    private var spineColour: Color {
        if member.isMutedByMe { return Theme.textFaint.opacity(0.5) }
        if !member.nearby     { return Theme.textFaint }
        return Theme.live
    }

    private var statusLine: String {
        if isPrivate          { return "DIRECT LINE — HOLDING" }
        if theyOpenedPrivate  { return "DIRECT LINE TO YOU" }
        if member.isMutedByMe { return "MUTED" }
        if member.isSpeaking  { return "SPEAKING" }
        return member.nearby ? "IN RANGE" : "CONNECTED"
    }

    private var statusColour: Color {
        if isPrivate || theyOpenedPrivate { return Theme.plate15 }
        if member.isMutedByMe             { return Theme.plate25 }
        if member.isSpeaking              { return Theme.live }
        return Theme.textFaint
    }
}
