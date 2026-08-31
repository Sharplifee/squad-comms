import SwiftUI

/// The microphone card — live level, sensitivity, and the transmit threshold.
///
/// This is the control that decides whether the app works at all. Open mic
/// means a threshold is deciding when your voice goes out, and if that number
/// is wrong you are either broadcasting your breathing or nobody hears you.
/// It has to be visible, live, and adjustable without leaving the screen —
/// tucked inside Settings it may as well not exist.
///
/// The waveform is not decoration. It is the only way to see where your voice
/// sits relative to the threshold before you find out the hard way.
struct MicCard: View {
    @EnvironmentObject private var audio: AudioCoordinator
    @EnvironmentObject private var session: SessionManager
    @State private var prefs = PreferencesStore.shared.current

    private let barCount = 26

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Button {
                    session.setSelfMuted(!session.selfMuted)
                    Haptics.impact(.medium)
                } label: {
                    Image(systemName: session.selfMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 19))
                        .foregroundStyle(session.selfMuted ? Theme.muted : Theme.live)
                        .frame(width: 46, height: 46)
                        .background(
                            Circle().fill((session.selfMuted ? Theme.muted : Theme.live).opacity(0.14))
                        )
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.selfMuted ? "Microphone muted" : "Microphone")
                        .font(.headline)
                    Text("Sensitivity \(Int(prefs.vadOnsetDB)) dB · \(sensitivityWord)")
                        .font(.caption)
                        .foregroundStyle(Theme.textDim)
                }

                Spacer()
            }

            // Live level against the threshold. The lit bars are what would
            // transmit right now at the current setting.
            waveform

            VStack(spacing: 6) {
                Slider(
                    value: Binding(
                        get: { Double(prefs.vadOnsetDB) },
                        set: { prefs.vadOnsetDB = Float($0) }
                    ),
                    in: -55 ... -12
                )
                HStack {
                    Text("Whisper").font(.caption2).foregroundStyle(Theme.textFaint)
                    Spacer()
                    Text("Shout").font(.caption2).foregroundStyle(Theme.textFaint)
                }
            }

            HStack {
                Circle()
                    .fill(audio.isTransmitting ? Theme.live : Theme.textFaint)
                    .frame(width: 7, height: 7)
                Text(audio.isTransmitting ? "Transmitting" : "Not transmitting")
                    .font(.caption)
                    .foregroundStyle(audio.isTransmitting ? Theme.live : Theme.textDim)
                Spacer()
                Text(wouldTransmit ? "WOULD TRANSMIT" : "SPEAK LOUDER")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textFaint)
            }
        }
        .padding(.vertical, 4)
        .onChange(of: prefs) { _, new in
            PreferencesStore.shared.update { $0 = new }
        }
    }

    private var waveform: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let spacing: CGFloat = 3
            let barWidth = (width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount)
            let level = normalisedLevel
            let threshold = normalisedThreshold

            ZStack(alignment: .leading) {
                HStack(spacing: spacing) {
                    ForEach(0..<barCount, id: \.self) { index in
                        let position = Double(index) / Double(barCount - 1)
                        let lit = position <= level && !session.selfMuted
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(lit ? Theme.live : Theme.surfaceAlt)
                            .frame(width: barWidth, height: barHeight(at: position, lit: lit))
                    }
                }
                .frame(height: 44)

                // Threshold marker. Draggable, because the number that matters
                // is the one you set while watching your own voice move.
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.warning)
                    .frame(width: 4, height: 44)
                    .offset(x: threshold * width - 2)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let fraction = min(max(value.location.x / width, 0), 1)
                                prefs.vadOnsetDB = Float(-55 + fraction * 43)
                            }
                    )
            }
        }
        .frame(height: 44)
    }

    private func barHeight(at position: Double, lit: Bool) -> CGFloat {
        guard lit else { return 6 }
        return 6 + CGFloat(abs(sin(position * 7)) * 26)
    }

    /// Input level mapped onto the -60…0 dB range the meter displays.
    private var normalisedLevel: Double {
        session.selfMuted ? 0 : min(max(Double(audio.inputLevelDB + 60) / 60, 0), 1)
    }

    private var normalisedThreshold: Double {
        min(max(Double(prefs.vadOnsetDB + 55) / 43, 0), 1)
    }

    private var wouldTransmit: Bool {
        !session.selfMuted && audio.inputLevelDB > prefs.vadOnsetDB
    }

    private var sensitivityWord: String {
        let words = ["Whisper", "Soft", "Low", "Medium", "Normal", "Elevated", "Loud", "Very loud", "Shout"]
        return words[min(8, Int(normalisedThreshold * 9))]
    }
}
