import SwiftUI

/// The radar and the people it found, as ONE object.
///
/// They were two separate cards showing the same information twice — a picture
/// of dots, then a list of the same dots by name, with a range control on each.
/// Fusing them makes the radar the panel's own header image: picture on top of
/// names, one thing rather than two that must be mentally joined.
///
/// The radar is also much smaller than it was. At 206pt it dominated a screen
/// whose actual question is "who is here"; at ~120 it answers that and gets out
/// of the way. Three rings rather than four, because a fourth ring at this size
/// is a line, not information.
struct NearbyPanel: View {
    let contacts: [ProximityEngine.Contact]
    let names: [UUID: String]
    let speakingID: UUID?
    let isScanning: Bool
    @Binding var rangeIndex: Int

    @State private var showRange = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            radar
            if showRange { rangeSlider }
            Divider().overlay(Theme.line)
            people
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Nearby")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Spacer()
            // The single range control. It used to exist twice on this screen,
            // in the radar header and the list header, driving one value.
            Button {
                withAnimation(.snappy(duration: 0.2)) { showRange.toggle() }
                Haptics.selection()
            } label: {
                HStack(spacing: 5) {
                    Text(ProximityEngine.rangeLabels[rangeIndex])
                        .font(.system(size: 12, design: .monospaced))
                    Image(systemName: showRange ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                }
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Theme.raised, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }

    private var rangeSlider: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(get: { Double(rangeIndex) },
                               set: { rangeIndex = Int($0.rounded()) }),
                in: 0...Double(ProximityEngine.rangeLabels.count - 1), step: 1
            )
            HStack {
                ForEach(Array(ProximityEngine.rangeTicks.enumerated()), id: \.offset) { offset, tick in
                    Text(tick)
                        .font(.system(size: 8))
                        .foregroundStyle(offset == rangeIndex ? Theme.text : Theme.dim)
                    if offset < ProximityEngine.rangeTicks.count - 1 { Spacer(minLength: 0) }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    // MARK: - Radar

    private var radar: some View {
        RadarStrip(contacts: contacts, names: names,
                   speakingID: speakingID, rangeIndex: rangeIndex,
                   reduceMotion: reduceMotion)
            .frame(height: 122)
            .padding(.horizontal, 16)
            .padding(.bottom, showRange ? 0 : 8)
    }

    // MARK: - People

    @ViewBuilder
    private var people: some View {
        if contacts.isEmpty {
            Text(isScanning ? "Nobody in range right now"
                            : "Bluetooth is off, so the radar can't see anyone")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
        } else {
            ForEach(Array(contacts.enumerated()), id: \.element.id) { index, contact in
                HStack(spacing: 13) {
                    Text(initials(names[contact.id] ?? "?"))
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .frame(width: 40, height: 40)
                        .background(Theme.raised,
                                    in: RoundedRectangle(cornerRadius: Theme.avatarCorner, style: .continuous))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(names[contact.id] ?? "Unknown device")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                        if contact.id == speakingID {
                            Text("Speaking")
                                .font(.caption)
                                .foregroundStyle(Theme.signal)
                        }
                    }

                    Spacer()

                    Text(distance(contact.metres))
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 13)

                if index < contacts.count - 1 {
                    Divider().overlay(Theme.line).padding(.leading, 71)
                }
            }
        }
    }

    private func initials(_ name: String) -> String {
        String(name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased()
    }

    /// Feet on a gym floor, miles once it is a drive. Nobody thinks in metres
    /// at either end.
    private func distance(_ metres: Double) -> String {
        metres < 91 ? "\(Int((metres * 3.28084).rounded())) ft"
                    : String(format: "%.1f mi", metres / 1609.34)
    }
}

/// The radar itself, sized as a strip rather than a hero.
struct RadarStrip: View {
    let contacts: [ProximityEngine.Contact]
    let names: [UUID: String]
    let speakingID: UUID?
    let rangeIndex: Int
    let reduceMotion: Bool

    @State private var sweep: Double = 0

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let radius = side / 2 - 6

            ZStack {
                // Three rings. A fourth at this size is a line, not data.
                ForEach(1...3, id: \.self) { ring in
                    Circle()
                        .strokeBorder(Theme.line, lineWidth: 0.7)
                        .frame(width: radius * 2 * CGFloat(ring) / 3,
                               height: radius * 2 * CGFloat(ring) / 3)
                }

                if !reduceMotion {
                    // Dimmed, and slower the further out you look — a sweep
                    // that races at 100 miles reads as agitation.
                    Rectangle()
                        .fill(LinearGradient(colors: [Theme.text.opacity(0.10), .clear],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 2, height: radius)
                        .offset(y: -radius / 2)
                        .rotationEffect(.degrees(sweep))
                }

                ForEach(contacts) { contact in
                    dot(contact, radius: radius)
                }

                Circle().fill(Theme.text).frame(width: 7, height: 7)
            }
            .frame(width: side, height: side)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: sweepPeriod).repeatForever(autoreverses: false)) {
                sweep = 360
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// 1.0s at 100 ft scaling to a 3.0s cap from a mile out.
    private var sweepPeriod: Double {
        min(3.0, 1.0 + Double(rangeIndex) * 0.5)
    }

    private func dot(_ contact: ProximityEngine.Contact, radius: CGFloat) -> some View {
        let angle = Double(abs(contact.id.hashValue) % 360) * .pi / 180
        let r = radius * contact.normalised
        let speaking = contact.id == speakingID
        return Circle()
            .fill(speaking ? Theme.signal : Theme.text)
            .frame(width: speaking ? 9 : 7, height: speaking ? 9 : 7)
            .opacity(speaking ? 1 : max(0.4, 1 - contact.normalised * 0.5))
            .offset(x: cos(angle) * r, y: sin(angle) * r)
            .animation(.easeInOut(duration: 0.6), value: contact.normalised)
    }

    private var spoken: String {
        guard !contacts.isEmpty else {
            return "Radar. Range \(ProximityEngine.rangeLabels[rangeIndex]). Nobody in range."
        }
        let described = contacts.map { contact -> String in
            let name = names[contact.id] ?? "Unknown device"
            let feet = Int((contact.metres * 3.28084).rounded())
            return "\(name), \(feet) feet\(contact.id == speakingID ? ", speaking" : "")"
        }
        return "Radar. \(described.joined(separator: ". "))"
    }
}
