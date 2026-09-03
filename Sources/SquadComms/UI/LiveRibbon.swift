import SwiftUI

/// Who is on, and how loud, as one object.
///
/// In the old build these were three separate things stacked down the screen:
/// a radar, a participant grid, and a waveform. All three answered a version
/// of the same question, and you had to read all three to get the answer.
///
/// Here the level meter is the background and the people ride on top of it. A
/// chip lights when that person is speaking, so presence and loudness are
/// literally the same picture — which is what you want when the phone is
/// coming out of a pocket mid-set for two seconds.
struct LiveRibbon: View {
    let members: [Member]
    let selfSpeaking: Bool
    let level: Float

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Double = 0

    private let barCount = 40

    var body: some View {
        ZStack {
            bars
            chips
        }
        .frame(height: 126)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    // MARK: - Level

    private var bars: some View {
        GeometryReader { geo in
            let width = geo.size.width - 32
            let spacing: CGFloat = 3
            let barWidth = (width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount)

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colour(at: index))
                        .frame(width: barWidth, height: height(at: index))
                }
            }
            .frame(width: width, height: geo.size.height - 28, alignment: .bottom)
            .position(x: geo.size.width / 2, y: geo.size.height - (geo.size.height - 28) / 2 - 14)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }

    /// Anyone speaking drives the meter, not just you — the ribbon is the
    /// state of the line, not the state of your microphone.
    private var active: Bool {
        selfSpeaking || members.contains { $0.isSpeaking && !$0.isMutedByMe }
    }

    private func height(at index: Int) -> CGFloat {
        guard active else { return 3 }
        let t = Double(index) / Double(barCount)
        let wave = abs(sin(t * 7 + phase)) * 0.6 + abs(sin(t * 3.1 + phase * 0.7)) * 0.4
        return 3 + CGFloat(wave) * 58
    }

    private func colour(at index: Int) -> Color {
        guard active else { return Theme.line }
        // Only the loud part of the meter takes the signal colour, so the
        // ribbon reads as a level rather than a solid block of yellow.
        return height(at: index) > 26 ? Theme.signal : Theme.signal.opacity(0.3)
    }

    // MARK: - People

    private var chips: some View {
        HStack(spacing: 9) {
            chip(name: PreferencesStore.shared.current.displayName,
                 live: selfSpeaking, isSelf: true)
            ForEach(members) { member in
                chip(name: member.displayName,
                     live: member.isSpeaking && !member.isMutedByMe,
                     isSelf: false)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }

    private func chip(name: String, live: Bool, isSelf: Bool) -> some View {
        HStack(spacing: 8) {
            Text(initials(name))
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(live ? Theme.base : Theme.text)
                .frame(width: 25, height: 25)
                .background(live ? Theme.signal : Theme.raised, in: Circle())
            Text(isSelf ? "You" : name)
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .lineLimit(1)
        }
        .padding(.leading, 6).padding(.trailing, 12).padding(.vertical, 6)
        .background(live ? Theme.signal.opacity(0.12) : Theme.base.opacity(0.85), in: Capsule())
        .overlay(Capsule().strokeBorder(live ? Theme.signal : Theme.line, lineWidth: 1))
        .animation(.easeInOut(duration: 0.18), value: live)
    }

    private func initials(_ name: String) -> String {
        String(name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased()
    }

    private var spoken: String {
        let talking = members.filter { $0.isSpeaking && !$0.isMutedByMe }.map(\.displayName)
        if selfSpeaking { return "You are transmitting." }
        if talking.isEmpty { return "Line open. Nobody talking." }
        return "\(talking.joined(separator: " and ")) talking."
    }
}
