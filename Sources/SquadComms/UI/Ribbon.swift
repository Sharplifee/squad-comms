import SwiftUI

/// The live line, as one object.
///
/// Replaces three separate things that were all answering the same question:
/// a radar, a participant grid, and a waveform. On an open line the only
/// question is who is talking and how loud — so presence rides directly on the
/// level meter rather than sitting in a card above it.
///
/// The chips are the people. A chip lights signal yellow when that person is
/// speaking, which is the same colour the bars use, so loudness and identity
/// read as one fact instead of two you have to correlate.
struct Ribbon: View {
    let members: [Member]
    let selfName: String
    let selfSpeaking: Bool
    let level: Double            // 0...1, current input level

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let barCount = 44

    var body: some View {
        ZStack {
            bars
            chips
        }
        .frame(height: 126)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var bars: some View {
        GeometryReader { geo in
            let width = geo.size.width - 32
            let spacing: CGFloat = 3
            let barWidth = (width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount)

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    let position = Double(index) / Double(barCount - 1)
                    // Louder pushes the lit edge further right; the shape comes
                    // from the position so it reads as a waveform rather than a
                    // progress bar.
                    let lit = position <= level
                    let height = lit
                        ? 8 + abs(sin(position * 9 + level * 6)) * 46
                        : 6
                    RoundedRectangle(cornerRadius: 2)
                        .fill(lit ? Theme.signal : Theme.line)
                        .frame(width: max(barWidth, 1), height: height)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: level)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 16)
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                chip(name: selfName, speaking: selfSpeaking, isSelf: true)
                ForEach(members) { member in
                    chip(name: member.displayName,
                         speaking: member.isSpeaking && !member.isMutedByMe,
                         isSelf: false)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(name: String, speaking: Bool, isSelf: Bool) -> some View {
        HStack(spacing: 8) {
            Text(initials(name))
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(speaking ? Theme.base : Theme.textDim)
                .frame(width: 25, height: 25)
                .background(speaking ? Theme.signal : Theme.raised, in: Circle())
            Text(isSelf ? "You" : name)
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.text)
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(speaking ? Theme.signal.opacity(0.12) : Theme.base.opacity(0.85))
        )
        .overlay(
            Capsule().strokeBorder(speaking ? Theme.signal : Theme.line, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.18), value: speaking)
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    private var spoken: String {
        let talking = members.filter { $0.isSpeaking && !$0.isMutedByMe }.map(\.displayName)
        if selfSpeaking { return "You are talking." }
        if talking.isEmpty { return "Nobody is talking. \(members.count + 1) on the line." }
        return "\(talking.joined(separator: " and ")) talking."
    }
}
