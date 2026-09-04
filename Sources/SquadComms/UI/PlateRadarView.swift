import SwiftUI

/// Who is near you, and how near.
///
/// Modelled on Find My rather than on a radar screen: concentric hairline
/// rings, no fill, no sweep arm, no colour coding by band. A rotating sweep and
/// coloured rings look like surveillance equipment; this is four people in a
/// gym. Distance is carried by position and by how solid a dot is, which is all
/// the information there actually is.
struct PlateRadarView: View {

    let contacts: [ProximityEngine.Contact]
    let rangeIndex: Int
    let names: [UUID: String]
    let speakingID: UUID?
    let isScanning: Bool

    @State private var pulse = false
    /// A rotating sweep is exactly the kind of continuous motion Reduce Motion
    /// exists to stop, and this one runs for the whole session.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let radius = side / 2 - 18

            ZStack {
                rings(radius: radius)
                ForEach(contacts) { contact in
                    dot(for: contact, radius: radius)
                }
                centre
            }
            .frame(width: side, height: side)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }

        .onAppear { pulse = !reduceMotion }
        // VoiceOver cannot read a picture of dots. The radar is the primary
        // content of this screen, so it has to say who is present and how far.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary)
    }

    /// What the radar would tell you if you could see it.
    private var spokenSummary: String {
        guard !contacts.isEmpty else {
            return "Radar. Range \(ProximityEngine.rangeLabels[rangeIndex]). Nobody in range."
        }
        let people = contacts.map { contact -> String in
            let name = names[contact.id] ?? "Unknown device"
            let metres = contact.metres
            let distance = metres < 91
                ? "\(Int((metres * 3.28084).rounded())) feet"
                : String(format: "%.1f miles", metres / 1609.34)
            let speaking = contact.id == speakingID ? ", speaking" : ""
            return "\(name), \(distance)\(speaking)"
        }
        return "Radar. Range \(ProximityEngine.rangeLabels[rangeIndex]). "
             + "^[\(contacts.count) person](inflect: true) in range: "
             + people.joined(separator: ". ")
    }

    // MARK: - Rings

    private func rings(radius: CGFloat) -> some View {
        ZStack {
            // Crosshairs and 45° diagonals. They cost nothing and they give the
            // eye something to measure bearing against — without them a dot at
            // two o'clock and one at three o'clock look identical.
            Path { path in
                path.move(to: CGPoint(x: -radius, y: 0)); path.addLine(to: CGPoint(x: radius, y: 0))
                path.move(to: CGPoint(x: 0, y: -radius)); path.addLine(to: CGPoint(x: 0, y: radius))
            }
            .stroke(Theme.hairline.opacity(0.55), lineWidth: 0.5)

            Path { path in
                let d = radius * 0.707
                path.move(to: CGPoint(x: -d, y: -d)); path.addLine(to: CGPoint(x: d, y: d))
                path.move(to: CGPoint(x: d, y: -d)); path.addLine(to: CGPoint(x: -d, y: d))
            }
            .stroke(Theme.hairline.opacity(0.3), lineWidth: 0.5)

            ForEach(0..<3, id: \.self) { index in
                let fraction = CGFloat(index + 1) / 3
                let r = radius * fraction
                Circle()
                    .strokeBorder(Theme.hairline, lineWidth: 0.5)
                    .frame(width: r * 2, height: r * 2)

                // What each ring actually means. A radar without distances is
                // a decoration.
                Text(ringLabel(fraction: Double(fraction)))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
                    .offset(y: -r + 9)
            }
        }
    }

    /// Ring distance in the unit a person would actually use at that scale.
    private func ringLabel(fraction: Double) -> String {
        let metres = ProximityEngine.rangeMetres[rangeIndex] * fraction
        if metres < 305 { return "\(Int((metres * 3.28084).rounded())) ft" }
        return String(format: "%.1f mi", metres / 1609.34)
    }

    // MARK: - People

    private func dot(for contact: ProximityEngine.Contact, radius: CGFloat) -> some View {
        // Bearing is derived from the identifier so a person keeps their place
        // between frames; only their distance from the centre moves.
        let angle = Double(abs(contact.id.hashValue) % 360) * .pi / 180
        let r = radius * contact.normalised
        let speaking = contact.id == speakingID
        let name = names[contact.id]

        return VStack(spacing: 5) {
            ZStack {
                if speaking {
                    Circle()
                        .fill(Theme.live.opacity(0.25))
                        .frame(width: 40, height: 40)
                        .scaleEffect(pulse ? 1.15 : 0.85)
                        .animation(reduceMotion ? nil
                                   : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                                   value: pulse)
                }
                Circle()
                    .fill(speaking ? Theme.live : Theme.accent)
                    .frame(width: 12, height: 12)
                    // Further away reads fainter. No hue change, because
                    // distance is a single continuous quantity.
                    .opacity(speaking ? 1 : 1 - contact.normalised * 0.45)
            }

            if let name {
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .offset(x: cos(angle) * r, y: sin(angle) * r)
        .animation(.easeInOut(duration: 0.6), value: contact.normalised)
    }

    // MARK: - You

    private var centre: some View {
        Circle()
            .fill(Theme.text)
            .frame(width: 10, height: 10)
            .overlay(
                Circle()
                    .strokeBorder(Theme.background, lineWidth: 2)
            )
    }
}

/// Range control, as a pill that opens the slider rather than a slider that is
/// always sitting there.
///
/// Range is set once and then left alone for the whole session, so a permanent
/// slider spends its life taking up space next to the radar for a control
/// nobody is touching. Collapsed it reads as a value; expanded it is a control.
struct RangeLoaderView: View {
    @Binding var index: Int
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.snappy(duration: 0.22)) { expanded.toggle() }
                Haptics.selection()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.caption)
                    Text(ProximityEngine.rangeLabels[index])
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                    Spacer()
                    if !expanded {
                        Text("Range")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textDim)
                    }
                }
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(spacing: 6) {
                    Slider(
                        value: Binding(
                            get: { Double(index) },
                            set: { index = Int($0.rounded()) }
                        ),
                        in: 0...Double(ProximityEngine.rangeLabels.count - 1),
                        step: 1
                    )

                    // Every stop labelled, so you can see where you are on a
                    // scale that is logarithmic and would otherwise feel
                    // arbitrary.
                    HStack {
                        ForEach(Array(ProximityEngine.rangeTicks.enumerated()), id: \.offset) { offset, tick in
                            Text(tick)
                                .font(.system(.caption2))
                                .foregroundStyle(offset == index ? Theme.accent : Theme.textFaint)
                            if offset < ProximityEngine.rangeTicks.count - 1 { Spacer(minLength: 0) }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 2)
    }
}
