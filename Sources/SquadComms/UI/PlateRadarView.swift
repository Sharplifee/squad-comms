import SwiftUI

/// The radar, drawn as a barbell seen end-on.
///
/// The range rings are not decorative circles at even percentages — they are
/// competition plates in real loading order, heaviest closest to the collar.
/// Red 25kg sits nearest you, then blue 20, yellow 15, green 10 furthest out.
/// A lifter reads distance bands the same way they read a loaded bar across
/// the gym floor, so the rings carry meaning instead of decoration.
struct PlateRadarView: View {

    let contacts: [ProximityEngine.Contact]
    let names: [UUID: String]
    let speakingID: UUID?
    let isScanning: Bool

    @State private var sweep: Double = 0

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let radius = side / 2 - 20

            ZStack {
                plates(radius: radius)
                if isScanning { sweepArm(radius: radius) }
                ForEach(contacts) { c in
                    dot(for: c, radius: radius)
                }
                collar
            }
            .frame(width: side, height: side)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) {
                sweep = 360
            }
        }
    }

    // MARK: - Plates

    private func plates(radius: CGFloat) -> some View {
        ForEach(Array(Theme.bands.enumerated().reversed()), id: \.offset) { index, colour in
            let fraction = CGFloat(index + 1) / CGFloat(Theme.bands.count)
            let r = radius * fraction

            ZStack {
                Circle()
                    .fill(colour.opacity(0.10))
                    .frame(width: r * 2, height: r * 2)
                Circle()
                    .stroke(colour.opacity(0.62), lineWidth: 2.5)
                    .frame(width: r * 2, height: r * 2)
                Text("\(Theme.bandWeights[index])kg")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(colour.opacity(0.85))
                    .offset(y: -r + 13)
            }
        }
    }

    // MARK: - Sweep

    private func sweepArm(radius: CGFloat) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Theme.text.opacity(0.30), Theme.text.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .frame(width: 2.5, height: radius)
            .offset(y: -radius / 2)
            .rotationEffect(.degrees(sweep))
    }

    // MARK: - Contacts

    private func dot(for c: ProximityEngine.Contact, radius: CGFloat) -> some View {
        // Angle is derived from the identifier so a person holds their bearing
        // between frames. Distance is the only thing that moves them.
        let angle = Double(abs(c.id.hashValue) % 360) * .pi / 180
        let r = radius * c.normalised
        let x = cos(angle) * r
        let y = sin(angle) * r
        let colour = Theme.color(for: c.normalised)
        let speaking = c.id == speakingID

        return ZStack {
            if speaking {
                Circle()
                    .stroke(colour, lineWidth: 2)
                    .frame(width: 34, height: 34)
                    .opacity(0.5)
                    .scaleEffect(speaking ? 1.25 : 1.0)
                    .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true),
                               value: speaking)
            }
            Circle()
                .fill(colour)
                .frame(width: 15, height: 15)
            Text((names[c.id] ?? "—").uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.text)
                .fixedSize()
                .offset(y: -19)
        }
        .offset(x: x, y: y)
    }

    // MARK: - You

    private var collar: some View {
        ZStack {
            Circle().fill(Theme.text).frame(width: 14, height: 14)
            Circle().stroke(Theme.text.opacity(0.30), lineWidth: 1.5)
                .frame(width: 24, height: 24)
        }
    }
}

/// The range control, phrased as loading a bar rather than setting a radius.
struct RangeLoaderView: View {
    @Binding var index: Int

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(ProximityEngine.rangeLabels[index])
                    .font(.system(size: 22, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.text)
                if index < ProximityEngine.rangeLabels.count - 1 {
                    Text("LOADED")
                        .font(.system(size: 10, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(Theme.textFaint)
                }
            }

            Slider(
                value: Binding(
                    get: { Double(index) },
                    set: { index = Int($0.rounded()) }
                ),
                in: 0...Double(ProximityEngine.rangeLabels.count - 1),
                step: 1
            )
            .tint(Theme.accent)
        }
    }
}
